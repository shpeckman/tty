# src/tty/readiness.cr
require "./syscall"

module TTY
  struct PollFd
    def initialize(@fd : Int32, @events : Int16, @revents : Int16)
    end

    def revents : Int16
      @revents
    end
  end

  enum IOEvent : Int16
    Readable = 1
    Writable = 4
  end

  POLL_ERROR   =  8_i16
  POLL_HUP     = 16_i16
  POLL_INVALID = 32_i16

  def self.wait_readable(fd : Int32, timeout_ms : Int32 = -1) : Bool
    wait_io(fd, IOEvent::Readable, timeout_ms)
  end

  def self.wait_writable(fd : Int32, timeout_ms : Int32 = -1) : Bool
    wait_io(fd, IOEvent::Writable, timeout_ms)
  end

  def self.wait_io(fd : Int32, events : IOEvent, timeout_ms : Int32 = -1) : Bool
    if fd < 0
      raise Syscall::Error.new(Syscall::EBADF, operation: "poll", fd: fd, request: events.value.to_u64)
    end
    raise ArgumentError.new("timeout_ms must be -1 or greater") if timeout_ms < -1

    mask = events.value | POLL_ERROR | POLL_HUP
    loop do
      pollfd = PollFd.new(fd, events.value, 0_i16)

      begin
        result = Syscall.poll(pointerof(pollfd).as(Pointer(Void)), 1_u64, timeout_ms)
      rescue ex : Syscall::Error
        next if ex.errno == Syscall::EINTR
        raise Syscall::Error.new(ex.errno, operation: ex.operation, fd: fd, request: events.value.to_u64)
      end

      return false if result == 0
      if (pollfd.revents & POLL_INVALID) != 0
        raise Syscall::Error.new(Syscall::EBADF, operation: "poll", fd: fd, request: events.value.to_u64)
      end
      return (pollfd.revents & mask) != 0
    end
  end
end
