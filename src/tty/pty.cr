# src/tty/pty.cr
require "./fd"
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

    def core_dumped? : Bool
      signaled? && (@status & 0x80) != 0
    end

    def success? : Bool
      exited? && exit_status == 0
    end
  end

  enum ChildEventKind
    None
    Exited
    Killed
    Dumped
    Trapped
    Stopped
    Continued
  end

  struct ChildEvent
    getter kind   : ChildEventKind
    getter pid    : Int32
    getter uid    : UInt32
    getter status : Int32

    def initialize(@kind : ChildEventKind, @pid : Int32, @uid : UInt32, @status : Int32)
    end

    def self.from_siginfo(info) : ChildEvent
      kind = case info.code
             when Syscall::CLD_EXITED
               ChildEventKind::Exited
             when Syscall::CLD_KILLED
               ChildEventKind::Killed
             when Syscall::CLD_DUMPED
               ChildEventKind::Dumped
             when Syscall::CLD_TRAPPED
               ChildEventKind::Trapped
             when Syscall::CLD_STOPPED
               ChildEventKind::Stopped
             when Syscall::CLD_CONTINUED
               ChildEventKind::Continued
             else
               ChildEventKind::None
             end
      new(kind, info.pid, info.uid, info.status)
    end

    def exited? : Bool
      kind == ChildEventKind::Exited
    end

    def exit_status : Int32
      status
    end

    def signaled? : Bool
      kind == ChildEventKind::Killed || kind == ChildEventKind::Dumped
    end

    def term_signal : Int32
      signaled? ? status : 0
    end

    def stopped? : Bool
      kind == ChildEventKind::Stopped
    end

    def stop_signal : Int32
      stopped? ? status : 0
    end

    def continued? : Bool
      kind == ChildEventKind::Continued
    end

    def trapped? : Bool
      kind == ChildEventKind::Trapped
    end

    def core_dumped? : Bool
      kind == ChildEventKind::Dumped
    end

    def terminal? : Bool
      exited? || signaled?
    end

    def success? : Bool
      exited? && status == 0
    end

    def wait_status : Int32
      case kind
      when ChildEventKind::Exited
        status << 8
      when ChildEventKind::Killed
        status
      when ChildEventKind::Dumped
        status | 0x80
      when ChildEventKind::Stopped
        0x7f | (status << 8)
      else
        0
      end
    end
  end

  struct SpawnOptions
    property env         : Hash(String, String)
    property winsize     : Winsize?
    property working_dir : String?
    property close_fds   : Bool

    def initialize(@env : Hash(String, String) = ENV.to_h, @winsize : Winsize? = nil, @working_dir : String? = nil, @close_fds : Bool = true)
    end
  end

  enum PacketKind
    Data
    Control
    EndOfStream
  end

  @[Flags]
  enum PacketEvent : UInt8
    Data       =  0
    FlushRead  =  1
    FlushWrite =  2
    Stop       =  4
    Start      =  8
    NoStop     = 16
    DoStop     = 32
  end

  struct Packet
    getter kind   : PacketKind
    getter events : PacketEvent
    getter size   : Int32

    def initialize(@kind : PacketKind, @events : PacketEvent, @size : Int32)
    end

    def self.data(size : Int32) : Packet
      new(PacketKind::Data, PacketEvent::Data, size)
    end

    def self.control(events : PacketEvent) : Packet
      new(PacketKind::Control, events, 0)
    end

    def self.end_of_stream : Packet
      new(PacketKind::EndOfStream, PacketEvent::Data, 0)
    end

    def data? : Bool
      kind == PacketKind::Data
    end

    def control? : Bool
      kind == PacketKind::Control
    end

    def end_of_stream? : Bool
      kind == PacketKind::EndOfStream
    end
  end

  class PTY
    getter master_fd  : Int32
    getter slave_fd   : Int32
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
          flags = (Syscall::O_RDWR | Syscall::O_NOCTTY | Syscall::O_CLOEXEC).to_i32
          slave = begin
            Syscall.ioctl_result(master, TIOCGPTPEER, flags)
          rescue ex : Syscall::Error
            case ex.errno
            when 22, 25, Syscall::ENOSYS
              Syscall.openat(name, Syscall::O_RDWR | Syscall::O_NOCTTY | Syscall::O_CLOEXEC)
            else
              raise ex
            end
          end
          return new(master, slave, name)
        {% end %}
      rescue ex
        begin
          Syscall.close(master)
        rescue
          nil
        end
        raise ex
      end
    end

    def self.spawn(command : String, args : Array(String) = [] of String, *, env : Hash(String, String) = ENV.to_h, winsize : Winsize? = nil, working_dir : String? = nil, close_fds : Bool = true) : Process
      spawn(command, args, SpawnOptions.new(env: env, winsize: winsize, working_dir: working_dir, close_fds: close_fds))
    end

    def self.spawn(command : String, args : Array(String) = [] of String, options : SpawnOptions = SpawnOptions.new) : Process
      pty = open
      options.winsize.try &.set(pty.master_fd)

      argv_strings = [command] + args
      argv_ptrs    = argv_strings.map(&.to_unsafe)
      argv_ptrs << Pointer(UInt8).null
      env_strings = options.env.map { |key, value| "#{key}=#{value}" }
      env_ptrs    = env_strings.map(&.to_unsafe)
      env_ptrs << Pointer(UInt8).null
      path_value = options.env["PATH"]? || ENV["PATH"]? || "/usr/bin:/bin"
      candidates = if command.includes?('/')
                     [command]
                   else
                     path_value.split(':').map { |dir| dir.empty? ? command : "#{dir}/#{command}" } + [command]
                   end

      error_read  = -1
      error_write = -1
      begin
        error_read, error_write = FD.pipe(cloexec: true)
      rescue ex
        pty.close
        raise ex
      end

      begin
        pid = Syscall.fork
      rescue ex
        Syscall.close(error_read)
        Syscall.close(error_write)
        pty.close
        raise ex
      end

      if pid == 0
        failure  = 0_i64
        error_fd = error_write
        Syscall.reset_child_signal_state
        Syscall.raw(Syscall::NR_CLOSE, error_read.to_i64)

        if working_dir = options.working_dir
          result  = Syscall.raw(Syscall::NR_CHDIR, working_dir.to_unsafe.address.to_i64)
          failure = result if failure == 0 && result < 0
        end

        result  = Syscall.raw(Syscall::NR_SETSID)
        failure = result if failure == 0 && result < 0
        result  = Syscall.raw(Syscall::NR_IOCTL, pty.slave_fd.to_i64, TIOCSCTTY.to_i64, 0_i64)
        failure = result if failure == 0 && result < 0
        result  = Syscall.raw(Syscall::NR_DUP2, pty.slave_fd.to_i64, 0_i64)
        failure = result if failure == 0 && result < 0
        result  = Syscall.raw(Syscall::NR_DUP2, pty.slave_fd.to_i64, 1_i64)
        failure = result if failure == 0 && result < 0
        result  = Syscall.raw(Syscall::NR_DUP2, pty.slave_fd.to_i64, 2_i64)
        failure = result if failure == 0 && result < 0
        Syscall.raw(Syscall::NR_CLOSE, pty.master_fd.to_i64)

        {% unless flag?(:darwin) %}
          if options.close_fds && failure == 0
            if error_fd != 3
              result = Syscall.raw(Syscall::NR_DUP3, error_fd.to_i64, 3_i64, Syscall::O_CLOEXEC)
              failure = result if result < 0
              error_fd = 3 if result >= 0
            end
            if failure == 0
              result = Syscall.raw(Syscall::NR_CLOSE_RANGE, 4_i64, Int32::MAX.to_i64, 0_i64)
              failure = result if result < 0
            end
          end
        {% end %}

        last_error = failure
        if failure == 0
          candidates.each do |path|
            result     = Syscall.raw(Syscall::NR_EXECVE, path.to_unsafe.address.to_i64, argv_ptrs.to_unsafe.address.to_i64, env_ptrs.to_unsafe.address.to_i64)
            last_error = result if result < 0
          end
        end

        error_number = last_error < 0 ? -last_error.to_i32 : 2_i32
        Syscall.raw(Syscall::NR_WRITE, error_fd.to_i64, pointerof(error_number).address.to_i64, 4_i64)
        Syscall.raw(Syscall::NR_CLOSE, error_fd.to_i64)
        Syscall.raw(Syscall::NR_EXIT_GROUP, 127_i64)
      end

      Syscall.close(error_write)
      pidfd = nil.as(Int32?)
      {% unless flag?(:darwin) %}
        begin
          pidfd = Syscall.pidfd_open(pid)
        rescue ex : Syscall::Error
          raise ex unless ex.errno == Syscall::ENOSYS || ex.errno == 22
        end
      {% end %}

      exec_errno = begin
        read_exec_error(error_read)
      ensure
        begin
          Syscall.close(error_read)
        rescue
          nil
        end
      end

      if exec_errno
        begin
          Syscall.wait4(pid)
        rescue
          nil
        end
        if fd = pidfd
          begin
            Syscall.close(fd)
          rescue
            nil
          end
        end
        pty.close
        raise ExecError.new(command, candidates, exec_errno)
      end

      begin
        pty.close_slave
      rescue ex
        begin
          Syscall.kill(pid, Syscall::SIGKILL)
        rescue
          nil
        end
        begin
          Syscall.wait4(pid)
        rescue
          nil
        end
        if fd = pidfd
          begin
            Syscall.close(fd)
          rescue
            nil
          end
        end
        begin
          pty.close
        rescue
          nil
        end
        raise ex
      end
      Process.new(pid, pty, pidfd)
    end

    def self.spawn(command : String, args : Array(String), env : Hash(String, String), winsize : Winsize? = nil) : Process
      spawn(command, args, SpawnOptions.new(env: env, winsize: winsize))
    end

    def self.wait(pid : Int32) : ChildStatus
      _, status = Syscall.wait4(pid)
      ChildStatus.new(status)
    end

    def initialize(@master_fd : Int32, @slave_fd : Int32, @slave_name : String)
    end

    def closed? : Bool
      @master_fd < 0
    end

    def close_slave : Nil
      return if @slave_fd < 0
      Syscall.close(@slave_fd)
      @slave_fd = -1
    end

    def locked? : Bool
      {% if flag?(:darwin) %}
        raise Error.new("PTY#locked? is Linux-only")
      {% else %}
        value = 0_i32
        Syscall.ioctl(@master_fd, TIOCGPTLCK, pointerof(value))
        value != 0
      {% end %}
    end

    def packet_mode? : Bool
      {% if flag?(:darwin) %}
        raise Error.new("PTY#packet_mode? is Linux-only")
      {% else %}
        value = 0_i32
        Syscall.ioctl(@master_fd, TIOCGPKT, pointerof(value))
        value != 0
      {% end %}
    end

    def packet_mode=(enabled : Bool) : Bool
      value = enabled ? 1_i32 : 0_i32
      Syscall.ioctl(@master_fd, TIOCPKT, pointerof(value))
      enabled
    end

    def read_packet(buffer : Bytes) : Packet
      raise Error.new("master fd is closed") if closed?
      raise ArgumentError.new("buffer must not be empty") if buffer.empty?
      scratch = Bytes.new(buffer.size + 1)
      count   = Syscall.read(@master_fd, scratch.to_unsafe, scratch.size)
      return Packet.end_of_stream if count == 0

      control = scratch[0]
      if control == 0
        data_size = count - 1
        buffer.copy_from(scratch[1, data_size]) if data_size > 0
        Packet.data(data_size)
      else
        Packet.control(PacketEvent.new(control))
      end
    end

    def master_io : IO::FileDescriptor
      raise Error.new("master fd is closed") if closed?
      IO::FileDescriptor.new(@master_fd)
    end

    def slave_io : IO::FileDescriptor
      raise Error.new("slave fd is closed") if @slave_fd < 0
      IO::FileDescriptor.new(@slave_fd)
    end

    def write_master(data : String) : Int32
      raise Error.new("master fd is closed") if closed?
      Syscall.write(@master_fd, data)
    end

    def write_slave(data : String) : Int32
      Syscall.write(effective_fd, data)
    end

    def read_master(buffer : Bytes) : Int32
      raise Error.new("master fd is closed") if closed?
      Syscall.read(@master_fd, buffer.to_unsafe, buffer.size)
    end

    def read_slave(buffer : Bytes) : Int32
      raise Error.new("slave fd is closed") if @slave_fd < 0
      Syscall.read(@slave_fd, buffer.to_unsafe, buffer.size)
    end

    def wait_readable(timeout_ms : Int32 = -1) : Bool
      TTY.wait_readable(@master_fd, timeout_ms)
    end

    def wait_priority(timeout_ms : Int32 = -1) : Bool
      TTY.wait_priority(@master_fd, timeout_ms)
    end

    def wait_writable(timeout_ms : Int32 = -1) : Bool
      TTY.wait_writable(@master_fd, timeout_ms)
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
      return if closed?
      Syscall.close(@master_fd)
      @master_fd = -1
    end

    private def effective_fd : Int32
      @slave_fd >= 0 ? @slave_fd : @master_fd
    end

    private def self.read_exec_error(fd : Int32) : Int32?
      value = 0_i32
      total = 0
      while total < 4
        begin
          pointer = pointerof(value).as(Pointer(UInt8)) + total
          bytes   = Syscall.read(fd, pointer, 4 - total)
          return nil if bytes == 0
          total += bytes
        rescue ex : Syscall::Error
          raise ex unless ex.errno == Syscall::EINTR
        end
      end
      value == 0 ? nil : value
    end

    class Process
      getter pid : Int32
      getter pty : PTY

      def initialize(@pid : Int32, @pty : PTY, @pidfd : Int32? = nil)
        @status     = nil.as(ChildStatus?)
        @last_event = nil.as(ChildEvent?)
      end

      def pidfd? : Int32?
        @pidfd
      end

      def pidfd : Int32
        {% if flag?(:darwin) %}
          raise Error.new("Process#pidfd is Linux-only")
        {% else %}
          if fd = @pidfd
            fd
          else
            fd = Syscall.pidfd_open(@pid)
            @pidfd = fd
            fd
          end
        {% end %}
      end

      def poll_exit(timeout_ms : Int32 = -1) : Bool
        TTY.wait_readable(pidfd, timeout_ms)
      end

      def wait : ChildStatus
        if status = @status
          status
        else
          _, raw_status = Syscall.wait4(@pid)
          @status = ChildStatus.new(raw_status)
        end
      end

      def wait(timeout_ms : Int32) : ChildStatus?
        raise ArgumentError.new("timeout_ms must be non-negative") if timeout_ms < 0
        return @status if @status

        remaining = timeout_ms
        loop do
          result, raw_status = Syscall.wait4(@pid, Syscall::WNOHANG)
          if result == @pid
            @status = ChildStatus.new(raw_status)
            return @status
          end
          return nil if remaining <= 0
          step = remaining < 10 ? remaining : 10
          Syscall.sleep_ms(step)
          remaining -= step
        end
      end

      def wait_event : ChildEvent
        {% if flag?(:darwin) %}
          raise Error.new("Process#wait_event is Linux-only")
        {% else %}
          if event = @last_event
            return event if event.terminal?
          end
          info = Syscall.waitid(Syscall::P_PID, @pid, Syscall::WEXITED | Syscall::WSTOPPED | Syscall::WCONTINUED)
          event = ChildEvent.from_siginfo(info)
          record_event(event)
          event
        {% end %}
      end

      def wait_event(timeout_ms : Int32) : ChildEvent?
        {% if flag?(:darwin) %}
          raise Error.new("Process#wait_event is Linux-only")
        {% else %}
          raise ArgumentError.new("timeout_ms must be non-negative") if timeout_ms < 0
          if event = @last_event
            return event if event.terminal?
          end

          remaining = timeout_ms
          loop do
            info = Syscall.waitid(Syscall::P_PID, @pid, Syscall::WEXITED | Syscall::WSTOPPED | Syscall::WCONTINUED | Syscall::WNOHANG)
            if info.pid == @pid
              event = ChildEvent.from_siginfo(info)
              record_event(event)
              return event
            end
            return nil if remaining <= 0
            step = remaining < 10 ? remaining : 10
            Syscall.sleep_ms(step)
            remaining -= step
          end
        {% end %}
      end

      def status : ChildStatus?
        @status
      end

      def last_event : ChildEvent?
        @last_event
      end

      def exited? : Bool
        !@status.nil?
      end

      def signal(signal : Int32) : Nil
        return if exited?
        if fd = @pidfd
          {% if flag?(:darwin) %}
            Syscall.kill(@pid, signal)
          {% else %}
            Syscall.pidfd_send_signal(fd, signal)
          {% end %}
        else
          Syscall.kill(@pid, signal)
        end
      end

      def terminate : Nil
        signal(Syscall::SIGTERM)
      end

      def kill : Nil
        signal(Syscall::SIGKILL)
      end

      def close : Nil
        if fd = @pidfd
          begin
            Syscall.close(fd)
          rescue
            nil
          end
          @pidfd = nil
        end
        @pty.close
      end

      private def record_event(event : ChildEvent) : Nil
        @last_event = event
        @status     = ChildStatus.new(event.wait_status) if event.terminal?
      end
    end

    class Error < TTY::Error
    end

    class ExecError < Error
      getter command  : String
      getter attempts : Array(String)
      getter errno    : Int32

      def initialize(@command : String, @attempts : Array(String), @errno : Int32)
        super("exec #{command} failed: #{errno_name} (errno #{errno})")
      end

      def errno_name : String
        Syscall::Error.errno_name_for(@errno)
      end
    end
  end
end
