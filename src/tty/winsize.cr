# src/tty/winsize.cr
@[Link("c")]
lib LibC
  {% unless LibC.has_constant?(:Winsize) %}
    struct Winsize
      ws_row : LibC::UShort
      ws_col : LibC::UShort
      ws_xpixel : LibC::UShort
      ws_ypixel : LibC::UShort
    end
  {% end %}

  {% unless LibC.has_method?(:ioctl) %}
    fun ioctl(fd : LibC::Int, request : LibC::ULong, ...) : LibC::Int
  {% end %}
end

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
