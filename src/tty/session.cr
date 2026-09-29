# src/tty/session.cr
require "./platform"
require "./syscall"

module TTY
  module Session
    def self.leader : Int32
      Syscall.setsid
    end

    def self.make_controlling(fd : Int32) : Nil
      Syscall.ioctl(fd, TIOCSCTTY, 0)
    end

    def self.foreground_pgrp(fd : Int32) : Int32
      pgrp = 0_i32
      Syscall.ioctl(fd, TIOCGPGRP, pointerof(pgrp))
      pgrp
    end

    def self.set_foreground_pgrp(fd : Int32, pgrp : Int32) : Nil
      value = pgrp
      Syscall.ioctl(fd, TIOCSPGRP, pointerof(value))
    end

    def self.exclusive(fd : Int32, enable : Bool = true) : Nil
      if enable
        Syscall.ioctl(fd, TIOCEXCL, 0)
      else
        Syscall.ioctl(fd, TIOCNXCL, 0)
      end
    end
  end
end
