# src/tty/winsize.cr
module TTY
  TIOCGWINSZ = 0x5413_u64
  TIOCSWINSZ = 0x5414_u64

  struct Winsize
    property rows   : UInt16
    property cols   : UInt16
    property xpixel : UInt16
    property ypixel : UInt16

    def initialize(@rows : UInt16 = 0_u16, @cols : UInt16 = 0_u16, @xpixel : UInt16 = 0_u16, @ypixel : UInt16 = 0_u16)
    end

    def self.get(fd : Int32) : Winsize
      winsize = new
      Syscall.ioctl(fd, TIOCGWINSZ, pointerof(winsize))
      winsize
    end

    def set(fd : Int32) : Nil
      copy = self
      Syscall.ioctl(fd, TIOCSWINSZ, pointerof(copy))
    end
  end
end
