# src/tty/termios2.cr
require "./platform"
require "./syscall"
require "./termios"

{% unless flag?(:darwin) %}
  module TTY
    struct Termios2
      @iflag : UInt32
      @oflag : UInt32
      @cflag : UInt32
      @lflag : UInt32
      @line : UInt8
      @cc : StaticArray(UInt8, NCCS)
      @ispeed : UInt32
      @ospeed : UInt32

      def initialize
        @iflag = 0_u32
        @oflag = 0_u32
        @cflag = 0_u32
        @lflag = 0_u32
        @line = 0_u8
        @cc = StaticArray(UInt8, NCCS).new(0_u8)
        @ispeed = 0_u32
        @ospeed = 0_u32
      end

      def self.get(fd : Int32) : Termios2
        termios = new
        Syscall.ioctl(fd, TCGETS2, pointerof(termios))
        termios
      end

      def self.from(termios : Termios) : Termios2
        copy = new
        copy.input = termios.input
        copy.output = termios.output
        copy.control = termios.control
        copy.local = termios.local
        copy.line = termios.line
        ControlChar.each { |cc| copy[cc] = termios[cc] }
        copy
      end

      def set(fd : Int32, action : SetAction = SetAction::Now) : Nil
        request = case action
                  in SetAction::Now   then TCSETS2
                  in SetAction::Drain then TCSETS2 + 1_u64
                  in SetAction::Flush then TCSETS2 + 2_u64
                  end
        copy = self
        Syscall.ioctl(fd, request, pointerof(copy))
      end

      def input : InputFlag
        InputFlag.new(@iflag)
      end

      def input=(flags : InputFlag) : InputFlag
        @iflag = flags.value
        flags
      end

      def output : OutputFlag
        OutputFlag.new(@oflag)
      end

      def output=(flags : OutputFlag) : OutputFlag
        @oflag = flags.value
        flags
      end

      def control : ControlFlag
        ControlFlag.new(@cflag)
      end

      def control=(flags : ControlFlag) : ControlFlag
        @cflag = flags.value
        flags
      end

      def local : LocalFlag
        LocalFlag.new(@lflag)
      end

      def local=(flags : LocalFlag) : LocalFlag
        @lflag = flags.value
        flags
      end

      def line : UInt8
        @line
      end

      def line=(discipline : UInt8) : UInt8
        @line = discipline
      end

      def [](cc : ControlChar) : UInt8
        @cc[cc.value]
      end

      def []=(cc : ControlChar, value : UInt8) : UInt8
        @cc[cc.value] = value
      end

      def input_speed : UInt32
        @ispeed
      end

      def output_speed : UInt32
        @ospeed
      end

      def custom_baud=(rate : UInt32) : UInt32
        @cflag = (@cflag & ~CBAUD_MASK) | ControlFlag::BOther.value
        @ispeed = rate
        @ospeed = rate
        rate
      end

      def custom_baud? : Bool
        (@cflag & CBAUD_MASK) == ControlFlag::BOther.value
      end
    end
  end
{% end %}
