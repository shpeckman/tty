# src/tty/winsize.cr
require "./platform"
require "./syscall"

module TTY
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

    def self.current(fd : Int32 = 0) : Winsize?
      get(fd)
    rescue ex : Syscall::Error
      raise ex unless ex.errno == Syscall::ENOTTY
      nil
    end

    def self.propagate(from_fd : Int32, to_fd : Int32) : Nil
      current(from_fd).try &.set(to_fd)
      TTY.on_resize(from_fd) { |size| size.set(to_fd) }
    end

    def set(fd : Int32) : Nil
      copy = self
      Syscall.ioctl(fd, TIOCSWINSZ, pointerof(copy))
    end
  end

  def self.on_resize(fd : Int32, &block : Winsize ->) : Nil
    Signal::WINCH.trap { block.call Winsize.get(fd) }
  end
end
