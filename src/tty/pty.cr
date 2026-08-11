# src/tty/pty.cr
require "./lib_c"
require "./terminal"

class TTY::Pty < IO
  {% if flag?(:darwin) %}
    POSIX_SPAWN_SETSID = 0x0400_i16
  {% else %}
    POSIX_SPAWN_SETSID = 0x0080_i16 # glibc; harmless where the flag is unused
  {% end %}

  SPAWN_ATTR_SIZE         = 512
  SPAWN_FILE_ACTIONS_SIZE = 512
  O_RDWR                  =   2
  DEFAULT_SIZE            = Winsize.new(80, 24)

  getter master  : IO::FileDescriptor
  getter process : Process

  getter? closed = false
  @exit_code : Int32? = nil
  @reaped = false

  def self.open(command : String, args : Enumerable(String) = [] of String,
                size : Winsize = DEFAULT_SIZE,
                env : Process::Env = nil, chdir : String? = nil, &)
    pty = new(command, args, size: size, env: env, chdir: chdir)
    begin
      yield pty
    ensure
      pty.kill
      pty.reap
    end
  end

  def initialize(command : String, args : Enumerable(String) = [] of String,
                 size : Winsize = DEFAULT_SIZE,
                 env : Process::Env = nil, chdir : String? = nil)
    master_fd = uninitialized LibC::Int
    slave_fd = uninitialized LibC::Int
    name_buffer = Bytes.new(256, 0_u8)

    ws = size.to_unsafe

    if LibC.openpty(pointerof(master_fd), pointerof(slave_fd),
         name_buffer.to_unsafe.as(LibC::Char*), Pointer(Void).null,
         pointerof(ws)) != 0
      raise RuntimeError.from_errno("openpty")
    end

    @master = IO::FileDescriptor.new master_fd
    slave   = IO::FileDescriptor.new slave_fd

    process = begin
      spawn_child command, args, master_fd, slave, slave_path(name_buffer),
        env, chdir
    rescue ex
      @master.close rescue nil
      slave.close rescue nil
      raise ex
    end
    @process = process

    slave.close
  end

  private def slave_path(name_buffer : Bytes) : String
    stop = name_buffer.index(0_u8) || name_buffer.size
    String.new(name_buffer[0, stop])
  end

  private def spawn_child(command, args : Enumerable(String), master_fd, slave, slave_path,
                          env, chdir) : Process
    if pid = spawn_via_posix_spawn(command, args, master_fd, slave_path, env, chdir)
      return Process.new(Crystal::System::Process.new(pid))
    end
    spawn_via_openpty command, args, slave, env, chdir
  end

  private def spawn_via_posix_spawn(command, args : Enumerable(String), master_fd, slave_path,
                                    env, chdir) : LibC::PidT?
    resolved = Process.find_executable(command)
    return nil unless resolved

    prior_dir = nil
    if dir = chdir
      prior_dir = Dir.current
      Dir.cd dir
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
        return nil unless LibC.posix_spawn_file_actions_addopen(
                            actions_ptr, 0, slave_c, O_RDWR, LibC::ModeT.new(0)) == 0
        return nil unless LibC.posix_spawn_file_actions_adddup2(actions_ptr, 0, 1) == 0
        return nil unless LibC.posix_spawn_file_actions_adddup2(actions_ptr, 0, 2) == 0
        return nil unless LibC.posix_spawn_file_actions_addclose(actions_ptr, master_fd) == 0

        argv = build_argv(resolved, args)
        envp = build_envp(env)

        pid = uninitialized LibC::PidT
        rc = LibC.posix_spawn(pointerof(pid), resolved.to_unsafe,
          actions_ptr, attr_ptr, argv, envp)
        rc == 0 ? pid : nil
      ensure
        LibC.posix_spawn_file_actions_destroy(actions_ptr)
      end
    ensure
      LibC.posix_spawnattr_destroy(attr_ptr)
      if dir = prior_dir
        Dir.cd dir
      end
    end
  end

  private def build_argv(command : String, args : Enumerable(String)) : LibC::Char**
    list = [command.to_unsafe]
    args.each { |a| list << a.to_unsafe }
    list << Pointer(LibC::Char).null
    list.to_unsafe
  end

  private def build_envp(env : Process::Env) : LibC::Char**
    merged = {} of String => String
    ENV.each { |k, v| merged[k] = v }
    if extra = env
      extra.each do |k, v|
        if v.nil?
          merged.delete k
        else
          merged[k] = v
        end
      end
    end
    list = merged.map { |k, v| "#{k}=#{v}".to_unsafe }
    list << Pointer(LibC::Char).null
    list.to_unsafe
  end

  private def spawn_via_openpty(command, args : Enumerable(String), slave, env, chdir) : Process
    base = {input: slave, output: slave, error: slave, env: env, chdir: chdir}
    if Process.find_executable("setsid")
      setsid_args = ["-c", command]
      args.each { |a| setsid_args << a }
      Process.new("setsid", setsid_args, **base)
    else
      Process.new(command, args.to_a, **base)
    end
  end

  def resize(size : Winsize) : Nil
    return if @closed
    size.apply @master
  end

  def resize(cols : Int32, rows : Int32) : Nil
    resize Winsize.new(cols, rows)
  end

  def read(slice : Bytes) : Int32
    @master.read(slice)
  end

  def write(slice : Bytes) : Nil
    return if @closed
    @master.write(slice)
    @master.flush
  end

  def write(data : String) : Nil
    write(data.to_slice)
  end

  def close : Nil
    return if @closed
    @closed = true
    @master.close rescue nil
  end

  def reap : Int32?
    return @exit_code if @reaped
    @reaped    = true
    @exit_code = (@process.wait.exit_code rescue nil)
  end

  def kill : Nil
    return if @closed
    begin
      @process.signal Signal::HUP unless @process.terminated?
    rescue
    end
    close
  end
end
