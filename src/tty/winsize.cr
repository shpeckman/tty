# src/tty/winsize.cr
require "./platform"
require "./syscall"

module TTY
  struct Winsize
    property rows : UInt16
    property cols : UInt16
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

  def self.on_resize(fd : Int32, & : Winsize ->) : Nil
    Signal::WINCH.trap { yield Winsize.get(fd) }
  end
end
