# src/tty/modes.cr
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

  {% unless LibC.has_constant?(:ICANON) %}
    ICANON = {% if flag?(:darwin) || flag?(:bsd) %} 0x00000100 {% else %} 2 {% end %}
  {% end %}

  {% unless LibC.has_constant?(:ECHO) %}
    ECHO = {% if flag?(:darwin) || flag?(:bsd) %} 0x00000008 {% else %} 8 {% end %}
  {% end %}

  {% unless LibC.has_constant?(:VMIN) %}
    VMIN = {% if flag?(:darwin) || flag?(:bsd) %} 16 {% else %} 6 {% end %}
  {% end %}

  {% unless LibC.has_constant?(:VTIME) %}
    VTIME = {% if flag?(:darwin) || flag?(:bsd) %} 17 {% else %} 5 {% end %}
  {% end %}
end

module TTY
  class RawMode
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

  class CBreakMode
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

      cbreak = @saved

      # Cast to the platform-specific type of c_lflag to ensure bitwise operations compile safely across OSes
      flag_type = typeof(cbreak.c_lflag)
      cbreak.c_lflag &= ~(flag_type.new(LibC::ICANON) | flag_type.new(LibC::ECHO))

      # Return immediately on every single byte read
      cbreak.c_cc[LibC::VMIN] = 1_u8
      cbreak.c_cc[LibC::VTIME] = 0_u8

      if LibC.tcsetattr(@io.fd, LibC::TCSANOW, pointerof(cbreak)) != 0
        raise RuntimeError.from_errno("tcsetattr")
      end
    end

    def restore : Nil
      return if @restored
      @restored = true
      LibC.tcsetattr(@io.fd, LibC::TCSANOW, pointerof(@saved))
    end
  end
end
