# src/tty/messages.cr
require "./winsize"
require "./token"

module TTY
  struct Write
    include MVU::Msg
    getter data : Bytes

    def initialize(@data : Bytes)
    end
  end

  struct Resize
    include MVU::Msg
    getter size : Winsize

    def initialize(@size : Winsize)
    end
  end

  struct Close
    include MVU::Msg
  end

  struct EOF
    include MVU::Msg
  end

  struct TokensDecoded
    include MVU::Msg
    getter tokens : Array(Token)

    def initialize(@tokens : Array(Token))
    end
  end

  struct ProcessExited
    include MVU::Msg
    getter code : Int32

    def initialize(@code : Int32)
    end
  end
end
