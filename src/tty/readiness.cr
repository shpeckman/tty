# src/tty/readiness.cr
require "./syscall"

module TTY
  @[Extern]
  struct PollFd
    property fd      : Int32
    property events  : Int16
    property revents : Int16

    def initialize(@fd : Int32, @events : Int16, @revents : Int16 = 0_i16)
    end

    def self.watch(fd : Int32, events : IOEvent) : PollFd
      new(fd, events.value)
    end

    def readable? : Bool
      (revents & IOEvent::Readable.value) != 0
    end

    def priority? : Bool
      (revents & IOEvent::Priority.value) != 0
    end

    def writable? : Bool
      (revents & IOEvent::Writable.value) != 0
    end

    def error? : Bool
      (revents & IOEvent::Error.value) != 0
    end

    def hangup? : Bool
      (revents & IOEvent::HangUp.value) != 0
    end

    def invalid? : Bool
      (revents & IOEvent::Invalid.value) != 0
    end
  end

  @[Flags]
  enum IOEvent : Int16
    Readable =  1
    Priority =  2
    Writable =  4
    Error    =  8
    HangUp   = 16
    Invalid  = 32
  end

  POLL_ERROR   = IOEvent::Error.value
  POLL_HUP     = IOEvent::HangUp.value
  POLL_INVALID = IOEvent::Invalid.value

  def self.poll(fds : Array(PollFd), timeout_ms : Int32 = -1) : Int32
    poll(Slice.new(fds.to_unsafe, fds.size), timeout_ms)
  end

  def self.poll(fds : Slice(PollFd), timeout_ms : Int32 = -1) : Int32
    raise ArgumentError.new("timeout_ms must be -1 or greater") if timeout_ms < -1
    return 0 if fds.empty?

    loop do
      begin
        return Syscall.poll(fds.to_unsafe.as(Pointer(Void)), fds.size.to_u64, timeout_ms)
      rescue ex : Syscall::Error
        raise ex unless ex.errno == Syscall::EINTR
      end
    end
  end

  def self.wait_readable(fd : Int32, timeout_ms : Int32 = -1) : Bool
    wait_io(fd, IOEvent::Readable, timeout_ms)
  end

  def self.wait_priority(fd : Int32, timeout_ms : Int32 = -1) : Bool
    wait_io(fd, IOEvent::Priority, timeout_ms)
  end

  def self.wait_writable(fd : Int32, timeout_ms : Int32 = -1) : Bool
    wait_io(fd, IOEvent::Writable, timeout_ms)
  end

  def self.wait_io(fd : Int32, events : IOEvent, timeout_ms : Int32 = -1) : Bool
    if fd < 0
      raise Syscall::Error.new(Syscall::EBADF, operation: "poll", fd: fd, request: events.value.to_u64)
    end
    raise ArgumentError.new("timeout_ms must be -1 or greater") if timeout_ms < -1

    mask = events.value | IOEvent::Error.value | IOEvent::HangUp.value
    loop do
      pollfd = PollFd.watch(fd, events)

      begin
        result = Syscall.poll(pointerof(pollfd).as(Pointer(Void)), 1_u64, timeout_ms)
      rescue ex : Syscall::Error
        next if ex.errno == Syscall::EINTR
        raise Syscall::Error.new(ex.errno, operation: ex.operation, fd: fd, request: events.value.to_u64)
      end

      return false if result == 0
      if pollfd.invalid?
        raise Syscall::Error.new(Syscall::EBADF, operation: "poll", fd: fd, request: events.value.to_u64)
      end
      return (pollfd.revents & mask) != 0
    end
  end
end
