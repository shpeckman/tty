# src/tty/pty.cr
module TTY
  TIOCSPTLCK = 0x40045431_u64
  TIOCGPTN   = 0x80045430_u64

  class PTY
    getter master_fd  : Int32
    getter slave_fd   : Int32
    getter slave_name : String

    def self.open : PTY
      master = Syscall.openat("/dev/ptmx", Syscall::O_RDWR | Syscall::O_NOCTTY | Syscall::O_CLOEXEC)
      begin
        unlock = 0_i32
        Syscall.ioctl(master, TIOCSPTLCK, pointerof(unlock))
        number = 0_u32
        Syscall.ioctl(master, TIOCGPTN, pointerof(number))
        name  = "/dev/pts/#{number}"
        slave = Syscall.openat(name, Syscall::O_RDWR | Syscall::O_NOCTTY | Syscall::O_CLOEXEC)
      rescue ex
        Syscall.close(master)
        raise ex
      end
      new(master, slave, name)
    end

    def initialize(@master_fd : Int32, @slave_fd : Int32, @slave_name : String)
    end

    def master_io : IO::FileDescriptor
      IO::FileDescriptor.new(@master_fd)
    end

    def slave_io : IO::FileDescriptor
      IO::FileDescriptor.new(@slave_fd)
    end

    def write_master(data : String) : Int32
      Syscall.write(@master_fd, data)
    end

    def write_slave(data : String) : Int32
      Syscall.write(@slave_fd, data)
    end

    def read_master(buffer : Bytes) : Int32
      Syscall.read(@master_fd, buffer.to_unsafe, buffer.size)
    end

    def read_slave(buffer : Bytes) : Int32
      Syscall.read(@slave_fd, buffer.to_unsafe, buffer.size)
    end

    def termios : Termios
      Termios.get(@slave_fd)
    end

    def termios=(termios : Termios) : Termios
      termios.set(@slave_fd)
      termios
    end

    def winsize : Winsize
      Winsize.get(@slave_fd)
    end

    def winsize=(winsize : Winsize) : Winsize
      winsize.set(@master_fd)
      winsize
    end

    def close : Nil
      Syscall.close(@slave_fd)
      Syscall.close(@master_fd)
    end
  end
end
