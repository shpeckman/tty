# src/tty/termios.cr
module TTY
  TCGETS  = 0x5401_u64
  TCSETS  = 0x5402_u64
  TCSETSW = 0x5403_u64
  TCSETSF = 0x5404_u64

  NCCS = 19

  TCFLSH = 0x540B_u64

  enum FlushQueue : Int32
    Input  = 0
    Output = 1
    Both   = 2
  end

  def self.flush(fd : Int32, queue : FlushQueue = FlushQueue::Both) : Nil
    Syscall.ioctl(fd, TCFLSH, queue.value)
  end

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

  struct Termios
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

    def self.get(fd : Int32) : Termios
      termios = new
      Syscall.ioctl(fd, TCGETS, pointerof(termios))
      termios
    end

    def set(fd : Int32, action : UInt64 = TCSETS) : Nil
      copy = self
      Syscall.ioctl(fd, action, pointerof(copy))
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
  end
end
