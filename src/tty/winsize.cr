# src/tty/winsize.cr
require "./conversions"
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

    def self.get(fd : Descriptor) : Winsize
      winsize = new
      Syscall.ioctl(TTY.fd_of(fd), TIOCGWINSZ, pointerof(winsize))
      winsize
    end

    def self.current(fd : Descriptor = 0) : Winsize?
      get(fd)
    rescue ex : Syscall::Error
      raise ex unless ex.errno == Syscall::ENOTTY
      nil
    end

    def self.propagate(from_fd : Descriptor, to_fd : Descriptor) : Nil
      source = TTY.fd_of(from_fd)
      target = TTY.fd_of(to_fd)
      current(source).try &.set(target)
      TTY.on_resize(source) { |size| size.set(target) }
    end

    def set(fd : Descriptor) : Nil
      copy = self
      Syscall.ioctl(TTY.fd_of(fd), TIOCSWINSZ, pointerof(copy))
    end
  end

  def self.on_resize(fd : Descriptor, &block : Winsize ->) : Nil
    source = fd_of(fd)
    Signal::WINCH.trap { block.call Winsize.get(source) }
  end
end
