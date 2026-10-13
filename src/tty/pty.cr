# src/tty/pty.cr
require "./conversions"
require "./fd"
require "./platform"
require "./readiness"
require "./syscall"
require "./termios"
require "./winsize"

module TTY
  module ExitStatusMethods
    def exit_code : Int32
      exit_status
    end

    def normal_exit? : Bool
      exited?
    end

    def signal_exit? : Bool
      signaled?
    end

    def exit_signal : ::Signal
      ::Signal.new(term_signal)
    end
  end

  struct ChildStatus
    include ExitStatusMethods

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
    include ExitStatusMethods

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

    def self.from_wait_status(pid : Int32, status : Int32) : ChildEvent
      if status & 0x7f == 0
        new(ChildEventKind::Exited, pid, 0_u32, (status >> 8) & 0xff)
      elsif status & 0xff == 0x7f
        new(ChildEventKind::Stopped, pid, 0_u32, (status >> 8) & 0xff)
      else
        kind = (status & 0x80) != 0 ? ChildEventKind::Dumped : ChildEventKind::Killed
        new(kind, pid, 0_u32, status & 0x7f)
      end
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
    DEFAULT_TERM = "xterm-256color"
    DEFAULT_PATH = "/usr/bin:/bin"
    SHELL        = "/bin/sh"
    SHELL_ARGS   = %("$@")

    getter env           : Hash(String, String?)
    property clear_env   : Bool
    property shell       : Bool
    property winsize     : Winsize?
    property working_dir : String?
    property close_fds   : Bool

    def initialize(env : ::Process::Env = nil, @clear_env : Bool = false, @shell : Bool = false, @winsize : Winsize? = nil, @working_dir : String? = nil, @close_fds : Bool = true)
      @env = Hash(String, String?).new
      self.env = env
    end

    def env=(env : ::Process::Env) : ::Process::Env
      @env = Hash(String, String?).new
      env.try &.each { |key, value| @env[key] = value }
      env
    end

    def environment : Hash(String, String)
      result = Hash(String, String).new
      unless clear_env
        result.merge!(ENV.to_h)
        result["TERM"] ||= DEFAULT_TERM
      end
      @env.each do |key, value|
        if value
          result[key] = value
        else
          result.delete(key)
        end
      end
      result
    end

    def argv(command : String, args : Array(String)) : Array(String)
      return [command] + args unless shell
      script = args.empty? || command.includes?(SHELL_ARGS) ? command : "#{command} #{SHELL_ARGS}"
      [SHELL, "-c", script, "sh"] + args
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

    property eof_on_error : Bool

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
            when Syscall::EINVAL, Syscall::ENOTTY, Syscall::ENOSYS
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

    def self.spawn(command : String, args : Array(String) = [] of String, **options) : Process
      spawn(command, args, SpawnOptions.new(**options))
    end

    def self.spawn(command : String, args : Array(String), options : SpawnOptions) : Process
      launch(open, command, args, options)
    end

    def self.spawn(command : String, args : Array(String) = [] of String, **options, & : Process -> U) : U forall U
      spawn(command, args, SpawnOptions.new(**options)) { |process| yield process }
    end

    def self.spawn(command : String, args : Array(String), options : SpawnOptions, & : Process -> U) : U forall U
      process = spawn(command, args, options)
      begin
        yield process
      ensure
        begin
          process.pty.close
          process.wait
        ensure
          process.close
        end
      end
    end

    def self.run(command : String, args : Array(String) = [] of String, **options) : Tuple(String, ChildStatus)
      run(command, args, SpawnOptions.new(**options))
    end

    def self.run(command : String, args : Array(String), options : SpawnOptions) : Tuple(String, ChildStatus)
      pty = open
      begin
        pty.modify_termios do |termios|
          termios.output &= ~OutputFlag::ONlcr
          termios
        end
      rescue ex
        pty.close
        raise ex
      end
      process = launch(pty, command, args, options)
      begin
        output = process.gets_to_end
        {output, process.wait}
      ensure
        process.close
      end
    end

    def self.wait(pid : Int32) : ChildStatus
      _, status = Syscall.wait4(pid)
      ChildStatus.new(status)
    end

    private def self.launch(pty : PTY, command : String, args : Array(String), options : SpawnOptions) : Process
      error_read  = -1
      error_write = -1
      begin
        options.winsize.try &.set(pty.master_fd)
        argv_strings = options.argv(command, args)
        environment  = options.environment
        env_strings  = environment.map { |key, value| "#{key}=#{value}" }
        path_value   = environment["PATH"]? || ENV["PATH"]? || SpawnOptions::DEFAULT_PATH
        executable   = argv_strings[0]
        candidates   = if executable.includes?('/')
                         [executable]
                       else
                         path_value.split(':').map { |dir| dir.empty? ? executable : "#{dir}/#{executable}" } + [executable]
                       end
        error_read, error_write = FD.pipe(cloexec: true)
      rescue ex
        pty.close
        raise ex
      end

      argv_ptrs = argv_strings.map(&.to_unsafe)
      argv_ptrs << Pointer(UInt8).null
      env_ptrs = env_strings.map(&.to_unsafe)
      env_ptrs << Pointer(UInt8).null

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
              result = Syscall.close_fds_from(4_i32, error_fd)
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
          raise ex unless ex.errno == Syscall::ENOSYS || ex.errno == Syscall::EINVAL
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

    def initialize(@master_fd : Int32, @slave_fd : Int32, @slave_name : String)
      @eof_on_error = true
      @evented_io   = nil.as(IO?)
      @adapters     = [] of Tuple(::IO::FileDescriptor, Int32)
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
        {% raise "TTY::PTY#locked? is Linux-only" %}
      {% else %}
        value = 0_i32
        Syscall.ioctl(@master_fd, TIOCGPTLCK, pointerof(value))
        value != 0
      {% end %}
    end

    def packet_mode? : Bool
      {% if flag?(:darwin) %}
        {% raise "TTY::PTY#packet_mode? is Linux-only" %}
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
      count = begin
        Syscall.read(@master_fd, scratch.to_unsafe, scratch.size)
      rescue ex : Syscall::Error
        return Packet.end_of_stream if @eof_on_error && ex.errno == Syscall::EIO
        raise ex
      end
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

    def master_io : ::IO::FileDescriptor
      raise Error.new("master fd is closed") if closed?
      adapter = ::IO::FileDescriptor.new(@master_fd, close_on_finalize: false)
      register_adapter(adapter, @master_fd)
      adapter
    end

    def slave_io : ::IO::FileDescriptor
      raise Error.new("slave fd is closed") if @slave_fd < 0
      adapter = ::IO::FileDescriptor.new(@slave_fd, close_on_finalize: false)
      register_adapter(adapter, @slave_fd)
      adapter
    end

    def io : IO
      raise Error.new("master fd is closed") if closed?
      @evented_io || IO.new(self)
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
      begin
        Syscall.read(@master_fd, buffer.to_unsafe, buffer.size)
      rescue ex : Syscall::Error
        return 0 if @eof_on_error && ex.errno == Syscall::EIO
        raise ex
      end
    end

    def read_master_v(buffers : Array(Bytes)) : Int32
      raise Error.new("master fd is closed") if closed?
      begin
        FD.readv(@master_fd, buffers)
      rescue ex : Syscall::Error
        return 0 if @eof_on_error && ex.errno == Syscall::EIO
        raise ex
      end
    end

    def write_master_v(buffers : Array(Bytes)) : Int32
      raise Error.new("master fd is closed") if closed?
      FD.writev(@master_fd, buffers)
    end

    def read_slave(buffer : Bytes) : Int32
      raise Error.new("slave fd is closed") if @slave_fd < 0
      Syscall.read(@slave_fd, buffer.to_unsafe, buffer.size)
    end

    def wait_readable(timeout : Timeout = nil) : Bool
      TTY.wait_readable(@master_fd, timeout)
    end

    def wait_priority(timeout : Timeout = nil) : Bool
      TTY.wait_priority(@master_fd, timeout)
    end

    def wait_writable(timeout : Timeout = nil) : Bool
      TTY.wait_writable(@master_fd, timeout)
    end

    def termios : Termios
      Termios.get(effective_fd)
    end

    def termios=(termios : Termios) : Termios
      termios.set(effective_fd)
      termios
    end

    def modify_termios(& : Termios -> Termios) : Termios
      self.termios = yield termios
    end

    def winsize : Winsize
      Winsize.get(effective_fd)
    end

    def winsize=(winsize : Winsize) : Winsize
      winsize.set(@master_fd)
      winsize
    end

    def close : Nil
      if io = @evented_io
        io.close
        return
      end
      close_adapters
      close_slave
      return if closed?
      Syscall.close(@master_fd)
      @master_fd = -1
    end

    protected def evented_io : IO?
      @evented_io
    end

    protected def evented_io=(io : IO) : Nil
      @evented_io = io
    end

    protected def io_closed : Nil
      @evented_io = nil
      @master_fd  = -1
      close_adapters
      close_slave
    end

    private def register_adapter(adapter : ::IO::FileDescriptor, fd : Int32) : Nil
      @adapters.reject! { |(kept, _)| kept.closed? }
      @adapters << {adapter, fd}
    end

    private def close_adapters : Nil
      @adapters.each do |(adapter, fd)|
        unless adapter.closed?
          begin
            adapter.close
          rescue ::IO::Error
            nil
          end
        end
        @master_fd = -1 if fd == @master_fd
        @slave_fd  = -1 if fd == @slave_fd
      end
      @adapters.clear
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

    class Process < ::IO
      RELAY_BUFFER_SIZE = 4096

      getter pid : Int32
      getter pty : PTY

      def initialize(@pid : Int32, @pty : PTY, @pidfd : Int32? = nil)
        @status     = nil.as(ChildStatus?)
        @last_event = nil.as(ChildEvent?)
      end

      def io : PTY::IO
        @pty.io
      end

      delegate expect, send_line, to: io

      def read(slice : Bytes) : Int32
        check_open
        io.read(slice)
      end

      def write(slice : Bytes) : Nil
        check_open
        io.write(slice)
      end

      def flush : Nil
        @pty.evented_io.try &.flush
      end

      def closed? : Bool
        @pty.closed?
      end

      def interact(input : ::IO::FileDescriptor = STDIN, output : ::IO = STDOUT) : ChildStatus
        source      = input.fd
        terminal    = input.tty?
        saved_flags = FD.status_flags(source)
        reader      = ::IO::FileDescriptor.new(FD.duplicate_cloexec(source))
        Winsize.propagate(source, @pty.master_fd) if terminal
        begin
          if terminal
            TTY.raw(source) { relay(reader, output) }
          else
            relay(reader, output)
          end
        ensure
          reader.close
          Syscall.fcntl(source, Syscall::F_SETFL, saved_flags.to_i64)
          ::Signal::WINCH.reset if terminal
        end
        wait
      end

      def pidfd? : Int32?
        @pidfd
      end

      def pidfd : Int32
        {% if flag?(:darwin) %}
          {% raise "TTY::PTY::Process#pidfd is Linux-only" %}
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

      def poll_exit(timeout : Timeout = nil) : Bool
        TTY.wait_readable(pidfd, timeout)
      end

      def wait : ChildStatus
        if status = @status
          status
        else
          begin
            _, raw_status = Syscall.wait4(@pid)
            record_reap(raw_status)
          rescue ex : Syscall::Error
            raise ex unless ex.errno == Syscall::ECHILD
            recover_status || raise ex
          end
        end
      end

      def wait(timeout : Int32 | Time::Span) : ChildStatus?
        remaining = bounded_timeout(timeout)
        return @status if @status

        if fd = @pidfd
          return nil unless TTY.wait_readable(fd, remaining)
          return wait
        end

        loop do
          begin
            result, raw_status = Syscall.wait4(@pid, Syscall::WNOHANG)
          rescue ex : Syscall::Error
            raise ex unless ex.errno == Syscall::ECHILD
            return recover_status || raise ex
          end
          return record_reap(raw_status) if result == @pid
          return nil if remaining <= 0
          step = remaining < 10 ? remaining : 10
          sleep step.milliseconds
          remaining -= step
        end
      end

      def wait_event : ChildEvent
        {% if flag?(:darwin) %}
          {% raise "TTY::PTY::Process#wait_event is Linux-only" %}
        {% else %}
          if event = @last_event
            return event if event.terminal?
          end
          wait_event_impl(Syscall::WEXITED | Syscall::WSTOPPED | Syscall::WCONTINUED).not_nil!
        {% end %}
      end

      def wait_event(timeout : Int32 | Time::Span) : ChildEvent?
        {% if flag?(:darwin) %}
          {% raise "TTY::PTY::Process#wait_event is Linux-only" %}
        {% else %}
          remaining = bounded_timeout(timeout)
          if event = @last_event
            return event if event.terminal?
          end

          loop do
            event = wait_event_impl(Syscall::WEXITED | Syscall::WSTOPPED | Syscall::WCONTINUED | Syscall::WNOHANG)
            return event if event
            return nil if remaining <= 0
            step = remaining < 10 ? remaining : 10
            sleep step.milliseconds
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

      def signal(signal : SignalValue) : Nil
        return if exited?
        number = TTY.signal_number(signal)
        if fd = @pidfd
          {% if flag?(:darwin) %}
            Syscall.kill(@pid, number)
          {% else %}
            Syscall.pidfd_send_signal(fd, number)
          {% end %}
        else
          Syscall.kill(@pid, number)
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

      private def relay(reader : ::IO::FileDescriptor, output : ::IO) : Nil
        channel = io
        ::spawn do
          buffer = Bytes.new(RELAY_BUFFER_SIZE)
          begin
            while (count = reader.read(buffer)) > 0
              channel.write(buffer[0, count])
            end
          rescue ::IO::Error
            nil
          end
        end
        buffer = Bytes.new(RELAY_BUFFER_SIZE)
        while (count = channel.read(buffer)) > 0
          output.write(buffer[0, count])
          output.flush
        end
      end

      private def bounded_timeout(timeout : Int32 | Time::Span) : Int32
        limit = TTY.timeout_ms(timeout)
        raise ArgumentError.new("timeout must be non-negative") if limit < 0
        limit
      end

      private def record_event(event : ChildEvent) : Nil
        @last_event = event
        return unless event.terminal?
        begin
          _, raw_status = Syscall.wait4(@pid)
          @status = ChildStatus.new(raw_status)
        rescue ex : Syscall::Error
          @status = ChildStatus.new(event.wait_status)
        end
      end

      private def record_reap(raw_status : Int32) : ChildStatus
        status  = ChildStatus.new(raw_status)
        @status = status
        unless @last_event.try &.terminal?
          @last_event = ChildEvent.from_wait_status(@pid, raw_status)
        end
        status
      end

      private def wait_event_impl(options : Int32) : ChildEvent?
        {% if flag?(:darwin) %}
          nil
        {% else %}
          info = begin
            Syscall.waitid(Syscall::P_PID, @pid, options | Syscall::WNOWAIT)
          rescue ex : Syscall::Error
            raise ex unless ex.errno == Syscall::ECHILD
            return recover_event || raise ex
          end
          return nil if info.pid == 0
          event = ChildEvent.from_siginfo(info)
          unless event.terminal?
            Syscall.waitid(Syscall::P_PID, @pid, Syscall::WEXITED | Syscall::WSTOPPED | Syscall::WCONTINUED)
          end
          record_event(event)
          event
        {% end %}
      end

      private def recover_status : ChildStatus?
        if status = @status
          status
        elsif raw_status = external_reap_status
          record_reap(raw_status)
        end
      end

      private def recover_event : ChildEvent?
        if event = @last_event
          return event if event.terminal?
        end
        if raw_status = external_reap_status
          record_reap(raw_status)
          @last_event
        end
      end

      private def external_reap_status : Int32?
        2.times do |attempt|
          if raw_status = ::Crystal::System::SignalChildHandler.wait(@pid).receive?
            return raw_status
          end
          Fiber.yield if attempt == 0
        end
        nil
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
