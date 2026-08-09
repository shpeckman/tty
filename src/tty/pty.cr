# src/tty/pty.cr

# The `lib LibC` block must reopen the *top-level* `LibC`, not a module-nested
# one, so the stdlib aliases like `LibC::UShort`/`LibC::ULong` resolve and this
# binding merges with the stdlib's. It therefore lives outside `module Term`.
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

    ws = LibC::Winsize.new
    ws.ws_row = rows.to_u16
    ws.ws_col = cols.to_u16

    if LibC.openpty(pointerof(master_fd), pointerof(slave_fd),
         Pointer(LibC::Char).null, Pointer(Void).null, pointerof(ws)) != 0
      raise RuntimeError.from_errno("openpty")
    end

    @master = IO::FileDescriptor.new master_fd
    slave   = IO::FileDescriptor.new slave_fd

    process = begin
      spawn_child command, args, slave, env, chdir
    rescue ex
      @master.close rescue nil
      slave.close rescue nil
      raise ex
    end
    @process = process

    slave.close
  end

  private def spawn_child(command, args, slave, env, chdir) : Process
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
