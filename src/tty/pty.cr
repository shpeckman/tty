# src/tty/pty.cr
require "./winsize"
require "./messages"
require "./tokenizer"

@[Link("c")]
lib LibC
  fun posix_spawn(pid : LibC::PidT*, path : LibC::Char*,
                  file_actions : Void*, attrp : Void*,
                  argv : LibC::Char**, envp : LibC::Char**) : LibC::Int
  fun posix_spawnp(pid : LibC::PidT*, file : LibC::Char*,
                   file_actions : Void*, attrp : Void*,
                   argv : LibC::Char**, envp : LibC::Char**) : LibC::Int

  fun posix_spawn_file_actions_init(fa : Void*) : LibC::Int
  fun posix_spawn_file_actions_destroy(fa : Void*) : LibC::Int
  fun posix_spawn_file_actions_addopen(fa : Void*, fildes : LibC::Int,
                                       path : LibC::Char*, oflag : LibC::Int,
                                       mode : LibC::ModeT) : LibC::Int
  fun posix_spawn_file_actions_adddup2(fa : Void*, fildes : LibC::Int,
                                       newfildes : LibC::Int) : LibC::Int
  fun posix_spawn_file_actions_addclose(fa : Void*, fildes : LibC::Int) : LibC::Int

  fun posix_spawnattr_init(attr : Void*) : LibC::Int
  fun posix_spawnattr_destroy(attr : Void*) : LibC::Int
  fun posix_spawnattr_setflags(attr : Void*, flags : LibC::Short) : LibC::Int
end

@[Link("util")]
lib LibC
  fun openpty(amaster : LibC::Int*, aslave : LibC::Int*, name : LibC::Char*,
              termp : Void*, winp : LibC::Winsize*) : LibC::Int
end

struct TTY::PTY
  include MVU::Model

  {% if flag?(:darwin) %}
    POSIX_SPAWN_SETSID = 0x0400_i16
  {% else %}
    POSIX_SPAWN_SETSID = 0x0080_i16
  {% end %}

  SPAWN_ATTR_SIZE         = 512
  SPAWN_FILE_ACTIONS_SIZE = 512
  O_RDWR                  =   2
  DEFAULT_SIZE            = Winsize.new(80, 24)

  getter master    : IO::FileDescriptor
  getter process   : Process
  getter size      : Winsize
  getter closed    : Bool
  getter io_closed : Bool
  getter exit_code : Int32?

  def self.spawn(command : String, args : Enumerable(String) = [] of String, size : Winsize = DEFAULT_SIZE, env : Process::Env = nil, chdir : String? = nil) : PTY
    master_fd = uninitialized LibC::Int
    slave_fd = uninitialized LibC::Int
    name_buffer = Bytes.new(256, 0_u8)

    ws = size.to_unsafe

    if LibC.openpty(pointerof(master_fd), pointerof(slave_fd), name_buffer.to_unsafe.as(LibC::Char*), Pointer(Void).null, pointerof(ws)) != 0
      raise RuntimeError.from_errno("openpty")
    end

    master = IO::FileDescriptor.new(master_fd)
    slave  = IO::FileDescriptor.new(slave_fd)

    process = begin
      spawn_child(command, args, master_fd, slave, slave_path(name_buffer), env, chdir)
    rescue ex
      master.close rescue nil
      slave.close rescue nil
      raise ex
    end

    slave.close

    new(master, process, size)
  end

  private def self.slave_path(name_buffer : Bytes) : String
    stop = name_buffer.index(0_u8) || name_buffer.size
    String.new(name_buffer[0, stop])
  end

  private def self.spawn_child(command, args : Enumerable(String), master_fd, slave, slave_path, env, chdir) : Process
    if pid = spawn_via_posix_spawn(command, args, master_fd, slave_path, env, chdir)
      return Process.new(Crystal::System::Process.new(pid))
    end
    spawn_via_openpty(command, args, slave, env, chdir)
  end

  private def self.spawn_via_posix_spawn(command, args : Enumerable(String), master_fd, slave_path, env, chdir) : LibC::PidT?
    resolved = Process.find_executable(command)
    return nil unless resolved

    prior_dir = nil
    if dir = chdir
      prior_dir = Dir.current
      Dir.cd(dir)
    end

    attr        = Bytes.new(SPAWN_ATTR_SIZE, 0_u8)
    actions     = Bytes.new(SPAWN_FILE_ACTIONS_SIZE, 0_u8)
    attr_ptr    = attr.to_unsafe.as(Void*)
    actions_ptr = actions.to_unsafe.as(Void*)

    return nil unless LibC.posix_spawnattr_init(attr_ptr) == 0
    begin
      return nil unless LibC.posix_spawnattr_setflags(attr_ptr, POSIX_SPAWN_SETSID) == 0
      return nil unless LibC.posix_spawn_file_actions_init(actions_ptr) == 0
      begin
        slave_c = slave_path.to_unsafe
        return nil unless LibC.posix_spawn_file_actions_addopen(actions_ptr, 0, slave_c, O_RDWR, LibC::ModeT.new(0)) == 0
        return nil unless LibC.posix_spawn_file_actions_adddup2(actions_ptr, 0, 1) == 0
        return nil unless LibC.posix_spawn_file_actions_adddup2(actions_ptr, 0, 2) == 0
        return nil unless LibC.posix_spawn_file_actions_addclose(actions_ptr, master_fd) == 0

        argv = build_argv(resolved, args)
        envp = build_envp(env)

        pid = uninitialized LibC::PidT
        rc = LibC.posix_spawn(pointerof(pid), resolved.to_unsafe, actions_ptr, attr_ptr, argv, envp)
        rc == 0 ? pid : nil
      ensure
        LibC.posix_spawn_file_actions_destroy(actions_ptr)
      end
    ensure
      LibC.posix_spawnattr_destroy(attr_ptr)
      if dir = prior_dir
        Dir.cd(dir)
      end
    end
  end

  private def self.build_argv(command : String, args : Enumerable(String)) : LibC::Char**
    list = [command.to_unsafe]
    args.each { |a| list << a.to_unsafe }
    list << Pointer(LibC::Char).null
    list.to_unsafe
  end

  private def self.build_envp(env : Process::Env) : LibC::Char**
    merged = {} of String => String
    ENV.each { |k, v| merged[k] = v }
    if extra = env
      extra.each do |k, v|
        if v.nil?
          merged.delete(k)
        else
          merged[k] = v
        end
      end
    end
    list = merged.map { |k, v| "#{k}=#{v}".to_unsafe }
    list << Pointer(LibC::Char).null
    list.to_unsafe
  end

  private def self.spawn_via_openpty(command, args : Enumerable(String), slave, env, chdir) : Process
    base = {input: slave, output: slave, error: slave, env: env, chdir: chdir}
    if Process.find_executable("setsid")
      setsid_args = ["-c", command]
      args.each { |a| setsid_args << a }
      Process.new("setsid", setsid_args, **base)
    else
      Process.new(command, args.to_a, **base)
    end
  end

  def initialize(@master : IO::FileDescriptor, @process : Process, @size : Winsize, @closed : Bool = false, @io_closed : Bool = false, @exit_code : Int32? = nil)
  end

  def update(msg : MVU::Msg) : {self, MVU::Cmd}
    case msg
    when Write
      cmd = MVU::Cmd.sync do
        unless @closed || @io_closed
          @master.write(msg.data)
          @master.flush
        end
        nil.as(MVU::Msg?)
      end
      {self, cmd}
    when Resize
      cmd = MVU::Cmd.sync do
        msg.size.apply(@master) unless @closed
        nil.as(MVU::Msg?)
      end
      {PTY.new(@master, @process, msg.size, @closed, @io_closed, @exit_code), cmd}
    when Close
      cmd = MVU::Cmd.sync do
        unless @closed
          begin
            @process.signal(Signal::HUP) unless @process.terminated?
          rescue
          end
          @master.close rescue nil
        end
        nil.as(MVU::Msg?)
      end
      {PTY.new(@master, @process, @size, true, true, @exit_code), cmd}
    when EOF
      {PTY.new(@master, @process, @size, @closed, true, @exit_code), MVU::Cmd.none}
    when ProcessExited
      {PTY.new(@master, @process, @size, @closed, @io_closed, msg.code), MVU::Cmd.none}
    else
      {self, MVU::Cmd.none}
    end
  end

  def view : String
    ""
  end

  def subscription_ids : Array(MVU::SubId)
    return MVU::Sub::NO_IDS if @closed

    ids = [] of MVU::SubId
    ids << :pty_read unless @io_closed
    ids << :pty_reap if @exit_code.nil?
    ids
  end

  def subscription(id : MVU::SubId) : MVU::Sub
    case id
    when :pty_read
      MVU::Sub.new(id) do |dispatch, cancel|
        buffer    = Bytes.new(4096)
        tokenizer = Tokenizer.new
        until cancel.closed?
          begin
            bytes_read = @master.read(buffer)
            if bytes_read > 0
              tokens = tokenizer.feed(buffer[0, bytes_read])
              dispatch.call(TokensDecoded.new(tokens)) unless tokens.empty?
            else
              dispatch.call(EOF.new)
            end
          rescue IO::Error
            dispatch.call(EOF.new) unless cancel.closed?
          end
        end
      end
    when :pty_reap
      MVU::Sub.new(id) do |dispatch, cancel|
        exit_code = begin
          @process.wait.exit_code
        rescue
          -1
        end
        unless cancel.closed?
          dispatch.call(ProcessExited.new(exit_code))
        end
      end
    else
      raise "TTY::PTY has no subscription for #{id.inspect}"
    end
  end
end
