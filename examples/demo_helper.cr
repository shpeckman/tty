# examples/demo_helper.cr
require "../src/tty"

@[Link("c")]
lib LibC
  {% unless LibC.has_constant?(:TCSANOW) %}
    TCSANOW = 0
  {% end %}

  TIOCGWINSZ = {% if flag?(:darwin) || flag?(:bsd) %} \
                 (0x40000000_u64 |
                  ((sizeof(LibC::Winsize).to_u64 & 0x1fff) << 16) |
                  ('t'.ord.to_u64 << 8) | 104_u64) \
               {% else %} 0x5413_u64 {% end %}

  {% unless LibC.has_constant?(:Termios) %}
    struct Termios
      c_iflag : UInt32
      c_oflag : UInt32
      c_cflag : UInt32
      c_lflag : UInt32
      c_line : UInt8
      c_cc : UInt8[32]
      c_ispeed : UInt32
      c_ospeed : UInt32
    end
  {% end %}

  {% unless LibC.has_method?(:tcgetattr) %}
    fun tcgetattr(fd : Int, termios_p : Termios*) : Int
  {% end %}
  {% unless LibC.has_method?(:tcsetattr) %}
    fun tcsetattr(fd : Int, optional_actions : Int, termios_p : Termios*) : Int
  {% end %}
  {% unless LibC.has_method?(:cfmakeraw) %}
    fun cfmakeraw(termios_p : Termios*) : Void
  {% end %}
end

class RawMode
  @saved : LibC::Termios

  def initialize(@fd : Int32)
    @saved = uninitialized LibC::Termios
    LibC.tcgetattr(@fd, pointerof(@saved))
    raw = @saved
    LibC.cfmakeraw(pointerof(raw))
    LibC.tcsetattr(@fd, LibC::TCSANOW, pointerof(raw))
  end

  def restore : Nil
    LibC.tcsetattr(@fd, LibC::TCSANOW, pointerof(@saved))
  end
end

def terminal_size(fd : Int32) : {Int32, Int32}
  ws = LibC::Winsize.new
  if LibC.ioctl(fd, LibC::TIOCGWINSZ, pointerof(ws)) == 0 && ws.ws_col > 0
    {ws.ws_col.to_i, ws.ws_row.to_i}
  else
    {80, 24}
  end
end