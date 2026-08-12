# src/tty/token.cr
module TTY::VT
  struct Token
    enum Kind : UInt8
      Text = 1
      C0; ESC; SS2; SS3; CSI
      OSC; DCS; APC; SOS; PM
    end

    getter kind       : Kind
    getter bytes      : Bytes
    getter? malformed : Bool

    def initialize(@kind : Kind, @bytes : Bytes, @malformed : Bool = false)
    end

    def size : Int32
      @bytes.size
    end

    def empty? : Bool
      @bytes.empty?
    end

    def text? : Bool
      @kind.text?
    end

    def control? : Bool
      @kind.c0?
    end

    def sequence? : Bool
      !text? && !control?
    end

    def string? : Bool
      case @kind
      when .osc?, .dcs?, .apc?, .sos?, .pm?
        true
      else
        false
      end
    end

    def clone : Token
      Token.new(@kind, @bytes.dup, @malformed)
    end

    def each_byte(& : UInt8 ->) : Nil
      @bytes.each { |byte| yield byte }
    end

    def [](index : Int) : UInt8
      @bytes[index]
    end

    def to_slice : Bytes
      @bytes
    end

    def to_s(io : IO) : Nil
      io.write_string(@bytes)
    end

    def inspect(io : IO) : Nil
      io << "TTY::VT::Token(" << @kind
      io << ", malformed" if @malformed
      io << ", "
      @bytes.each_with_index do |byte, index|
        io << ' ' if index > 0
        byte.to_s(io, base: 16, precision: 2)
      end
      io << ')'
    end

    def ==(other : Token) : Bool
      @kind == other.kind && @malformed == other.malformed? && @bytes == other.bytes
    end
  end
end

