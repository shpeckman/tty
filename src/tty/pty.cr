# src/tty/pty.cr

# The `lib LibC` block must reopen the *top-level* `LibC`, not a module-nested
# one, so the stdlib aliases like `LibC::UShort`/`LibC::ULong` resolve and this
# binding merges with the stdlib's. It therefore lives outside `TTY`.
@[Link("util")]
lib LibC
  {% unless LibC.has_constant?(:Winsize) %}
    struct Winsize
      ws_row : LibC::UShort
      ws_col : LibC::UShort
      ws_xpixel : LibC::UShort
      ws_ypixel : LibC::UShort
    end
  {% end %}

  fun openpty(amaster : LibC::Int*, aslave : LibC::Int*, name : LibC::Char*,
              termp : Void*, winp : LibC::Winsize*) : LibC::Int

  {% unless LibC.has_method?(:ioctl) %}
    fun ioctl(fd : LibC::Int, request : LibC::ULong, ...) : LibC::Int
  {% end %}

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

class TTY::Pty
  {% if flag?(:darwin) || flag?(:bsd) %}
    TIOCSWINSZ = (0x80000000_u64 |
                  ((sizeof(LibC::Winsize).to_u64 & 0x1fff) << 16) |
                  ('t'.ord.to_u64 << 8) | 103_u64)
  {% elsif flag?(:solaris) %}
    TIOCSWINSZ = 0x5467_u64
  {% else %}
    TIOCSWINSZ = 0x5414_u64 # Linux (and the default for anything else)
  {% end %}

  {% if flag?(:darwin) %}
    POSIX_SPAWN_SETSID = 0x0400_i16
  {% else %}
    POSIX_SPAWN_SETSID = 0x0080_i16 # glibc; harmless where the flag is unused
  {% end %}

  SPAWN_ATTR_SIZE         = 512
  SPAWN_FILE_ACTIONS_SIZE = 512
  O_RDWR                  =   2

  getter master : IO::FileDescriptor

  getter process : Process

  getter? closed = false
  @exit_code : Int32? = nil
  @reaped = false

  def initialize(command : String, args : Array(String) = [] of String,
                 cols : Int32 = 80, rows : Int32 = 24,
                 env : Process::Env = nil, chdir : String? = nil)
    master_fd = uninitialized LibC::Int
    slave_fd = uninitialized LibC::Int
    name_buffer = Bytes.new(256, 0_u8)

    ws = LibC::Winsize.new
    ws.ws_row = rows.to_u16
    ws.ws_col = cols.to_u16

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

  private def spawn_child(command, args, master_fd, slave, slave_path,
                          env, chdir) : Process
    if pid = spawn_via_posix_spawn(command, args, master_fd, slave_path, env, chdir)
      return Process.new(Crystal::System::Process.new(pid))
    end
    spawn_via_openpty command, args, slave, env, chdir
  end

  private def spawn_via_posix_spawn(command, args, master_fd, slave_path,
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

  private def build_argv(command : String, args : Array(String)) : LibC::Char**
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

  private def spawn_via_openpty(command, args, slave, env, chdir) : Process
    base = {input: slave, output: slave, error: slave, env: env, chdir: chdir}
    if Process.find_executable("setsid")
      Process.new("setsid", ["-c", command] + args, **base)
    else
      Process.new(command, args, **base)
    end
  end

  def resize(cols : Int32, rows : Int32) : Nil
    return if @closed
    ws = LibC::Winsize.new
    ws.ws_row = rows.to_u16
    ws.ws_col = cols.to_u16
    if LibC.ioctl(@master.fd, TIOCSWINSZ, pointerof(ws)) != 0
      raise RuntimeError.from_errno("ioctl(TIOCSWINSZ)")
    end
  end

  def write(data : Bytes | String) : Nil
    return if @closed
    @master.write data.to_slice
    @master.flush
  end

  def reap : Int32?
    return @exit_code if @reaped
    @reaped    = true
    @exit_code = (@process.wait.exit_code rescue nil)
  end

  def kill : Nil
    return if @closed
    @closed = true
    begin
      @process.signal Signal::HUP unless @process.terminated?
    rescue
    end
    @master.close rescue nil
  end
end
