# src/tty/termios.cr
require "./platform"
require "./syscall"

module TTY
  enum SetAction : UInt64
    Now   = TCSETS
    Drain = TCSETSW
    Flush = TCSETSF
  end

  enum FlushQueue : Int32
    {% if flag?(:darwin) %}
      Input  = 1
      Output = 2
      Both   = 3
    {% else %}
      Input  = 0
      Output = 1
      Both   = 2
    {% end %}
  end

  def self.flush(fd : Int32, queue : FlushQueue = FlushQueue::Both) : Nil
    {% if flag?(:darwin) %}
      Syscall.ioctl(fd, TIOCFLUSH, queue.value)
    {% else %}
      Syscall.ioctl(fd, TCFLSH, queue.value)
    {% end %}
  end

  {% if flag?(:darwin) %}
    @[Flags]
    enum InputFlag : UInt32
      IgnBrk  =    0x1
      BrkInt  =    0x2
      IgnPar  =    0x4
      ParMrk  =    0x8
      InPck   =   0x10
      IStrip  =   0x20
      Inlcr   =   0x40
      IgnCr   =   0x80
      ICrNl   =  0x100
      IXon    =  0x200
      IXoff   =  0x400
      IXany   =  0x800
      IMaxBel = 0x2000
      IUtf8   = 0x4000
    end

    @[Flags]
    enum OutputFlag : UInt32
      OPost  =    0x1
      ONlcr  =    0x2
      OXtabs =    0x4
      ONoeot =    0x8
      OCrnl  =   0x10
      ONocr  =   0x20
      ONlret =   0x40
      OFill  =   0x80
    end

    @[Flags]
    enum ControlFlag : UInt32
      CS5    =     0x0
      CS6    =   0x100
      CS7    =   0x200
      CS8    =   0x300
      CSize  =   0x300
      CStopB =   0x400
      CRead  =   0x800
      ParEnb =  0x1000
      ParOdd =  0x2000
      HupCl  =  0x4000
      CLocal =  0x8000
    end

    @[Flags]
    enum LocalFlag : UInt32
      EchoKe  =         0x1
      EchoE   =         0x2
      EchoK   =         0x4
      Echo    =         0x8
      EchoNl  =        0x10
      EchoPrt =        0x20
      EchoCtl =        0x40
      ISig    =        0x80
      ICanon  =       0x100
      IExten  =       0x400
      ToStop  =    0x400000
      FlushO  =    0x800000
      PendIn  =  0x20000000
      NoFlsh  =  0x80000000_u32
    end

    enum ControlChar : UInt8
      Eof     =  0
      Eol     =  1
      Eol2    =  2
      Erase   =  3
      WErase  =  4
      Kill    =  5
      Reprint =  6
      Intr    =  8
      Quit    =  9
      Susp    = 10
      Start   = 12
      Stop    = 13
      LNext   = 14
      Discard = 15
      Min     = 16
      Time    = 17
    end

    enum Baud : UInt32
      B0      =     0
      B50     =    50
      B75     =    75
      B110    =   110
      B134    =   134
      B150    =   150
      B200    =   200
      B300    =   300
      B600    =   600
      B1200   =  1200
      B1800   =  1800
      B2400   =  2400
      B4800   =  4800
      B9600   =  9600
      B19200  = 19200
      B38400  = 38400
      B7200   =  7200
      B14400  = 14400
      B28800  = 28800
      B57600  = 57600
      B76800  = 76800
      B115200 = 115200
      B230400 = 230400
    end
  {% else %}
    @[Flags]
    enum InputFlag : UInt32
      IgnBrk  = 0o0000001
      BrkInt  = 0o0000002
      IgnPar  = 0o0000004
      ParMrk  = 0o0000010
      InPck   = 0o0000020
      IStrip  = 0o0000040
      Inlcr   = 0o0000100
      IgnCr   = 0o0000200
      ICrNl   = 0o0000400
      IUclc   = 0o0001000
      IXon    = 0o0002000
      IXany   = 0o0004000
      IXoff   = 0o0010000
      IMaxBel = 0o0020000
      IUtf8   = 0o0040000
    end

    @[Flags]
    enum OutputFlag : UInt32
      OPost  = 0o0000001
      OLcuc  = 0o0000002
      ONlcr  = 0o0000004
      OCrnl  = 0o0000010
      ONocr  = 0o0000020
      ONlret = 0o0000040
      OFill  = 0o0000100
      OFdel  = 0o0000200
      NlDly  = 0o0000400
      CrDly  = 0o0003000
      TabDly = 0o0014000
      BsDly  = 0o0020000
      VtDly  = 0o0040000
      FfDly  = 0o0100000
    end

    @[Flags]
    enum ControlFlag : UInt32
      CS5    = 0o0000000
      CS6    = 0o0000020
      CS7    = 0o0000040
      CS8    = 0o0000060
      CSize  = 0o0000060
      CStopB = 0o0000100
      CRead  = 0o0000200
      ParEnb = 0o0000400
      ParOdd = 0o0001000
      HupCl  = 0o0002000
      CLocal = 0o0004000
      BOther = 0o0010000
      CBaud  = 0o0010017
    end

    @[Flags]
    enum LocalFlag : UInt32
      ISig    = 0o0000001
      ICanon  = 0o0000002
      XCase   = 0o0000004
      Echo    = 0o0000010
      EchoE   = 0o0000020
      EchoK   = 0o0000040
      EchoNl  = 0o0000100
      NoFlsh  = 0o0000200
      ToStop  = 0o0000400
      EchoCtl = 0o0001000
      EchoPrt = 0o0002000
      EchoKe  = 0o0004000
      FlushO  = 0o0010000
      PendIn  = 0o0040000
      IExten  = 0o0100000
    end

    enum ControlChar : UInt8
      Intr     =  0
      Quit     =  1
      Erase    =  2
      Kill     =  3
      Eof      =  4
      Time     =  5
      Min      =  6
      Swtc     =  7
      Start    =  8
      Stop     =  9
      Susp     = 10
      Eol      = 11
      Reprint  = 12
      Discard  = 13
      WErase   = 14
      LNext    = 15
      Eol2     = 16
    end

    enum Baud : UInt32
      B0       = 0o0000000
      B50      = 0o0000001
      B75      = 0o0000002
      B110     = 0o0000003
      B134     = 0o0000004
      B150     = 0o0000005
      B200     = 0o0000006
      B300     = 0o0000007
      B600     = 0o0000010
      B1200    = 0o0000011
      B1800    = 0o0000012
      B2400    = 0o0000013
      B4800    = 0o0000014
      B9600    = 0o0000015
      B19200   = 0o0000016
      B38400   = 0o0000017
      B57600   = 0o0010001
      B115200  = 0o0010002
      B230400  = 0o0010003
      B460800  = 0o0010004
      B500000  = 0o0010005
      B576000  = 0o0010006
      B921600  = 0o0010007
      B1000000 = 0o0010010
      B1152000 = 0o0010011
      B1500000 = 0o0010012
      B2000000 = 0o0010013
      B2500000 = 0o0010014
      B3000000 = 0o0010015
      B3500000 = 0o0010016
      B4000000 = 0o0010017
    end
  {% end %}

  {% if flag?(:darwin) %}
    CC_NAMES = [
      {ControlChar::Eof, "eof"}, {ControlChar::Eol, "eol"}, {ControlChar::Eol2, "eol2"},
      {ControlChar::Erase, "erase"}, {ControlChar::WErase, "werase"}, {ControlChar::Kill, "kill"},
      {ControlChar::Reprint, "rprnt"}, {ControlChar::Intr, "intr"}, {ControlChar::Quit, "quit"},
      {ControlChar::Susp, "susp"}, {ControlChar::Start, "start"}, {ControlChar::Stop, "stop"},
      {ControlChar::LNext, "lnext"}, {ControlChar::Discard, "flush"},
      {ControlChar::Min, "min"}, {ControlChar::Time, "time"},
    ]
  {% else %}
    CC_NAMES = [
      {ControlChar::Intr, "intr"}, {ControlChar::Quit, "quit"}, {ControlChar::Erase, "erase"},
      {ControlChar::Kill, "kill"}, {ControlChar::Eof, "eof"}, {ControlChar::Time, "time"},
      {ControlChar::Min, "min"}, {ControlChar::Swtc, "swtch"}, {ControlChar::Start, "start"},
      {ControlChar::Stop, "stop"}, {ControlChar::Susp, "susp"}, {ControlChar::Eol, "eol"},
      {ControlChar::Reprint, "rprnt"}, {ControlChar::Discard, "flush"}, {ControlChar::WErase, "werase"},
      {ControlChar::LNext, "lnext"}, {ControlChar::Eol2, "eol2"},
    ]
  {% end %}

  struct Termios
    {% if flag?(:darwin) %}
      @iflag : UInt64
      @oflag : UInt64
      @cflag : UInt64
      @lflag : UInt64
      @cc : StaticArray(UInt8, NCCS)
      @ispeed : UInt64
      @ospeed : UInt64

      def initialize
        @iflag = 0_u64
        @oflag = 0_u64
        @cflag = 0_u64
        @lflag = 0_u64
        @cc = StaticArray(UInt8, NCCS).new(0_u8)
        @ispeed = 0_u64
        @ospeed = 0_u64
      end
    {% else %}
      @iflag : UInt32
      @oflag : UInt32
      @cflag : UInt32
      @lflag : UInt32
      @line : UInt8
      @cc : StaticArray(UInt8, NCCS)

      def initialize
        @iflag = 0_u32
        @oflag = 0_u32
        @cflag = 0_u32
        @lflag = 0_u32
        @line = 0_u8
        @cc = StaticArray(UInt8, NCCS).new(0_u8)
      end
    {% end %}

    def self.get(fd : Int32) : Termios
      termios = new
      Syscall.ioctl(fd, TCGETS, pointerof(termios))
      termios
    end

    def set(fd : Int32, action : SetAction = SetAction::Now) : Nil
      copy = self
      Syscall.ioctl(fd, action.value, pointerof(copy))
    end

    def input : InputFlag
      InputFlag.new(@iflag.to_u32)
    end

    def input=(flags : InputFlag) : InputFlag
      {% if flag?(:darwin) %}
        @iflag = flags.value.to_u64
      {% else %}
        @iflag = flags.value.to_u32
      {% end %}
      flags
    end

    def output : OutputFlag
      OutputFlag.new(@oflag.to_u32)
    end

    def output=(flags : OutputFlag) : OutputFlag
      {% if flag?(:darwin) %}
        @oflag = flags.value.to_u64
      {% else %}
        @oflag = flags.value.to_u32
      {% end %}
      flags
    end

    def control : ControlFlag
      ControlFlag.new(@cflag.to_u32)
    end

    def control=(flags : ControlFlag) : ControlFlag
      {% if flag?(:darwin) %}
        @cflag = flags.value.to_u64
      {% else %}
        @cflag = flags.value.to_u32
      {% end %}
      flags
    end

    def local : LocalFlag
      LocalFlag.new(@lflag.to_u32)
    end

    def local=(flags : LocalFlag) : LocalFlag
      {% if flag?(:darwin) %}
        @lflag = flags.value.to_u64
      {% else %}
        @lflag = flags.value.to_u32
      {% end %}
      flags
    end

    {% if flag?(:darwin) %}
      def line : UInt8
        0_u8
      end

      def line=(discipline : UInt8) : UInt8
        discipline
      end
    {% else %}
      def line : UInt8
        @line
      end

      def line=(discipline : UInt8) : UInt8
        @line = discipline
      end
    {% end %}

    def [](cc : ControlChar) : UInt8
      @cc[cc.value]
    end

    def []=(cc : ControlChar, value : UInt8) : UInt8
      @cc[cc.value] = value
    end

    def baud : Baud
      {% if flag?(:darwin) %}
        Baud.new(@ispeed.to_u32)
      {% else %}
        Baud.new(@cflag & CBAUD_MASK)
      {% end %}
    end

    def baud=(rate : Baud) : Baud
      {% if flag?(:darwin) %}
        @ispeed = rate.value.to_u64
        @ospeed = rate.value.to_u64
      {% else %}
        @cflag = (@cflag & ~CBAUD_MASK) | rate.value
      {% end %}
      rate
    end

    def custom_baud? : Bool
      {% if flag?(:darwin) %}
        false
      {% else %}
        (@cflag & CBAUD_MASK) == ControlFlag::BOther.value
      {% end %}
    end

    def read_timeout=(timeout : Time::Span?) : Nil
      if timeout.nil?
        self[ControlChar::Min] = 1_u8
        self[ControlChar::Time] = 0_u8
      else
        deciseconds = (timeout.total_milliseconds / 100).round.to_i
        raise ArgumentError.new("read_timeout must fit in 0..255 deciseconds") unless 0 <= deciseconds <= 255
        self[ControlChar::Min] = 0_u8
        self[ControlChar::Time] = deciseconds.to_u8
      end
    end

    def read_timeout : Time::Span?
      if self[ControlChar::Min] == 1_u8 && self[ControlChar::Time] == 0_u8
        nil
      else
        (self[ControlChar::Time].to_i * 100).milliseconds
      end
    end

    def make_raw : Nil
      self.input = input & ~(InputFlag::IgnBrk | InputFlag::BrkInt | InputFlag::ParMrk |
                             InputFlag::IStrip | InputFlag::Inlcr | InputFlag::IgnCr |
                             InputFlag::ICrNl | InputFlag::IXon)
      self.output = output & ~OutputFlag::OPost
      self.local = local & ~(LocalFlag::Echo | LocalFlag::EchoNl | LocalFlag::ICanon |
                             LocalFlag::ISig | LocalFlag::IExten)
      self.control = (control & ~(ControlFlag::CSize | ControlFlag::ParEnb)) | ControlFlag::CS8
      self[ControlChar::Min] = 1_u8
      self[ControlChar::Time] = 0_u8
    end

    def make_cbreak : Nil
      self.local = local & ~(LocalFlag::ICanon | LocalFlag::Echo)
      self[ControlChar::Min] = 1_u8
      self[ControlChar::Time] = 0_u8
    end

    def to_s(io : IO) : Nil
      io << "speed " << baud.to_s.lchop('B') << " baud; line " << line << ";\n"
      CC_NAMES.each do |(cc, name)|
        value = self[cc]
        io << name << " = "
        if value == 0
          io << "<undef>"
        elsif value < 32
          io << '^' << (value ^ 0x40).chr
        else
          io << value.chr
        end
        io << "; "
      end
      io << '\n'
      io << flag_line(input)
      io << '\n'
      io << flag_line(output)
      io << '\n'
      cs = control & ControlFlag::CSize
      io << (case cs
             when ControlFlag::CS5 then "cs5 "
             when ControlFlag::CS6 then "cs6 "
             when ControlFlag::CS7 then "cs7 "
             else                       "cs8 "
             end)
      io << flag_line(control)
      io << '\n'
      io << flag_line(local)
    end

    private def flag_line(flags : F) : String forall F
      String.build do |io|
        F.each do |flag|
          io << '-' unless flags.includes?(flag)
          io << flag.to_s.downcase << ' '
        end
      end
    end

    private def flag_line(flags : ControlFlag) : String
      String.build do |io|
        ControlFlag.each do |flag|
          {% if flag?(:darwin) %}
            next if flag == ControlFlag::CS5 || flag == ControlFlag::CS6 || flag == ControlFlag::CS7 ||
                    flag == ControlFlag::CS8 || flag == ControlFlag::CSize
          {% else %}
            next if flag == ControlFlag::CS5 || flag == ControlFlag::CS6 || flag == ControlFlag::CS7 ||
                    flag == ControlFlag::CS8 || flag == ControlFlag::CSize || flag == ControlFlag::CBaud ||
                    flag == ControlFlag::BOther
          {% end %}
          io << '-' unless flags.includes?(flag)
          io << flag.to_s.downcase << ' '
        end
      end
    end
  end
end
