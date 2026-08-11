# src/tty/raw_mode.cr
@[Link("c")]
lib LibC
  {% unless LibC.has_constant?(:TCSANOW) %}
    TCSANOW = 0
  {% end %}

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
    fun tcgetattr(fd : LibC::Int, termios_p : Termios*) : LibC::Int
  {% end %}
  {% unless LibC.has_method?(:tcsetattr) %}
    fun tcsetattr(fd : LibC::Int, optional_actions : LibC::Int, termios_p : Termios*) : LibC::Int
  {% end %}
  {% unless LibC.has_method?(:cfmakeraw) %}
    fun cfmakeraw(termios_p : Termios*) : Void
  {% end %}
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
