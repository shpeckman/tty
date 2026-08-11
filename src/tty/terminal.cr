# src/tty/terminal.cr
require "./lib_c"

struct TTY::Winsize
  {% if flag?(:darwin) || flag?(:bsd) %}
    TIOCGWINSZ = (0x40000000_u64 |
                  ((sizeof(LibC::Winsize).to_u64 & 0x1fff) << 16) |
                  ('t'.ord.to_u64 << 8) | 104_u64)
    TIOCSWINSZ = (0x80000000_u64 |
                  ((sizeof(LibC::Winsize).to_u64 & 0x1fff) << 16) |
                  ('t'.ord.to_u64 << 8) | 103_u64)
  {% elsif flag?(:solaris) %}
    TIOCGWINSZ = 0x5468_u64
    TIOCSWINSZ = 0x5467_u64
  {% else %}
    TIOCGWINSZ = 0x5413_u64
    TIOCSWINSZ = 0x5414_u64
  {% end %}

  getter cols   : Int32
  getter rows   : Int32
  getter xpixel : Int32
  getter ypixel : Int32

  def self.from(io : IO::FileDescriptor) : Winsize?
    ws = LibC::Winsize.new
    return nil unless LibC.ioctl(io.fd, TIOCGWINSZ, pointerof(ws)) == 0
    return nil if ws.ws_col.zero?
    new ws.ws_col.to_i, ws.ws_row.to_i, ws.ws_xpixel.to_i, ws.ws_ypixel.to_i
  end

  def initialize(@cols : Int32, @rows : Int32, @xpixel : Int32 = 0, @ypixel : Int32 = 0)
  end

  def apply(io : IO::FileDescriptor) : Nil
    ws = to_unsafe
    if LibC.ioctl(io.fd, TIOCSWINSZ, pointerof(ws)) != 0
      raise RuntimeError.from_errno("ioctl(TIOCSWINSZ)")
    end
  end

  def to_unsafe : LibC::Winsize
    ws = LibC::Winsize.new
    ws.ws_row = @rows.to_u16
    ws.ws_col = @cols.to_u16
    ws.ws_xpixel = @xpixel.to_u16
    ws.ws_ypixel = @ypixel.to_u16
    ws
  end
end

class TTY::RawMode
  getter io : IO::FileDescriptor
  getter? restored = false

  @saved : LibC::Termios

  def self.open(io : IO::FileDescriptor, &)
    mode = new(io)
    begin
      yield mode
    ensure
      mode.restore
    end
  end

  def initialize(@io : IO::FileDescriptor)
    @saved = uninitialized LibC::Termios
    if LibC.tcgetattr(@io.fd, pointerof(@saved)) != 0
      raise RuntimeError.from_errno("tcgetattr")
    end
    raw = @saved
    LibC.cfmakeraw(pointerof(raw))
    if LibC.tcsetattr(@io.fd, LibC::TCSANOW, pointerof(raw)) != 0
      raise RuntimeError.from_errno("tcsetattr")
    end
  end

  def restore : Nil
    return if @restored
    @restored = true
    LibC.tcsetattr(@io.fd, LibC::TCSANOW, pointerof(@saved))
  end
end
