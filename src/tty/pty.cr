# src/tty/pty.cr
require "./platform"
require "./syscall"
require "./termios"
require "./winsize"

module TTY
  struct ChildStatus
    def initialize(@status : Int32)
    end

    def exited? : Bool
      @status & 0x7f == 0
    end

    def exit_status : Int32
      (@status >> 8) & 0xff
    end

    def signaled? : Bool
      term_signal != 0 && !stopped?
    end

    def term_signal : Int32
      @status & 0x7f
    end

    def stopped? : Bool
      @status & 0xff == 0x7f
    end

    def success? : Bool
      exited? && exit_status == 0
    end
  end

  class PTY
    getter master_fd : Int32
    getter slave_fd : Int32
    getter slave_name : String

    def self.open : PTY
      master = Syscall.openat("/dev/ptmx", Syscall::O_RDWR | Syscall::O_NOCTTY | Syscall::O_CLOEXEC)
      begin
        {% if flag?(:darwin) %}
          buffer = uninitialized UInt8[128]
          Syscall.ioctl(master, TIOCPTYGNAME, buffer.to_unsafe)
          darwin_name = String.new(buffer.to_unsafe)
          darwin_slave = Syscall.openat(darwin_name, Syscall::O_RDWR | Syscall::O_NOCTTY | Syscall::O_CLOEXEC)
          return new(master, darwin_slave, darwin_name)
        {% else %}
          unlock = 0_i32
          Syscall.ioctl(master, TIOCSPTLCK, pointerof(unlock))
          number = 0_u32
          Syscall.ioctl(master, TIOCGPTN, pointerof(number))
          name = "/dev/pts/#{number}"
          slave = Syscall.openat(name, Syscall::O_RDWR | Syscall::O_NOCTTY | Syscall::O_CLOEXEC)
          return new(master, slave, name)
        {% end %}
      rescue ex
        Syscall.close(master)
        raise ex
      end
    end

    def self.spawn(command : String, args : Array(String) = [] of String, env : Hash(String, String) = ENV.to_h, winsize : Winsize? = nil) : Tuple(Int32, PTY)
      pty = open
      winsize.try &.set(pty.master_fd)

      argv_strings = [command] + args
      argv_ptrs = argv_strings.map(&.to_unsafe)
      argv_ptrs << Pointer(UInt8).null
      env_strings = env.map { |key, value| "#{key}=#{value}" }
      env_ptrs = env_strings.map(&.to_unsafe)
      env_ptrs << Pointer(UInt8).null
      candidates = if command.includes?('/')
                     [command]
                   else
                     ENV["PATH"].split(':').map { |dir| "#{dir}/#{command}" } + [command]
                   end

      pid = Syscall.fork
      if pid == 0
        Syscall.raw(Syscall::NR_SETSID)
        Syscall.raw(Syscall::NR_IOCTL, pty.slave_fd.to_i64, TIOCSCTTY.to_i64, 0_i64)
        Syscall.raw(Syscall::NR_DUP2, pty.slave_fd.to_i64, 0_i64)
        Syscall.raw(Syscall::NR_DUP2, pty.slave_fd.to_i64, 1_i64)
        Syscall.raw(Syscall::NR_DUP2, pty.slave_fd.to_i64, 2_i64)
        Syscall.raw(Syscall::NR_CLOSE, pty.master_fd.to_i64)
        candidates.each do |path|
          Syscall.raw(Syscall::NR_EXECVE, path.to_unsafe.address.to_i64, argv_ptrs.to_unsafe.address.to_i64, env_ptrs.to_unsafe.address.to_i64)
        end
        Syscall.raw(Syscall::NR_EXIT_GROUP, 127_i64)
      end

      pty.close_slave
      {pid, pty}
    end

    def self.wait(pid : Int32) : ChildStatus
      _, status = Syscall.wait4(pid)
      ChildStatus.new(status)
    end

    def initialize(@master_fd : Int32, @slave_fd : Int32, @slave_name : String)
    end

    def close_slave : Nil
      return if @slave_fd < 0
      Syscall.close(@slave_fd)
      @slave_fd = -1
    end

    def master_io : IO::FileDescriptor
      IO::FileDescriptor.new(@master_fd)
    end

    def slave_io : IO::FileDescriptor
      raise Error.new("slave fd is closed") if @slave_fd < 0
      IO::FileDescriptor.new(@slave_fd)
    end

    def write_master(data : String) : Int32
      Syscall.write(@master_fd, data)
    end

    def write_slave(data : String) : Int32
      Syscall.write(effective_fd, data)
    end

    def read_master(buffer : Bytes) : Int32
      Syscall.read(@master_fd, buffer.to_unsafe, buffer.size)
    end

    def read_slave(buffer : Bytes) : Int32
      raise Error.new("slave fd is closed") if @slave_fd < 0
      Syscall.read(@slave_fd, buffer.to_unsafe, buffer.size)
    end

    def termios : Termios
      Termios.get(effective_fd)
    end

    def termios=(termios : Termios) : Termios
      termios.set(effective_fd)
      termios
    end

    def winsize : Winsize
      Winsize.get(effective_fd)
    end

    def winsize=(winsize : Winsize) : Winsize
      winsize.set(@master_fd)
      winsize
    end

    def close : Nil
      close_slave
      Syscall.close(@master_fd)
    end

    private def effective_fd : Int32
      @slave_fd >= 0 ? @slave_fd : @master_fd
    end

    class Error < Exception
    end
  end
end
