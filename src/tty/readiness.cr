# src/tty/readiness.cr
require "./syscall"

lib LibTTYPoll
  struct PollFd
    fd      : Int32
    events  : Int16
    revents : Int16
  end

  fun poll(fds : PollFd*, nfds : UInt64, timeout : Int32) : Int32
end

module TTY
  enum IOEvent : Int16
    Readable = 1
    Writable = 4
  end

  POLL_ERROR   =  8_i16
  POLL_HUP     = 16_i16
  POLL_INVALID = 32_i16

  def self.wait_readable(fd : Int32, timeout : Time::Span? = nil) : Bool
    wait_io(fd, IOEvent::Readable, timeout)
  end

  def self.wait_writable(fd : Int32, timeout : Time::Span? = nil) : Bool
    wait_io(fd, IOEvent::Writable, timeout)
  end

  def self.wait_io(fd : Int32, events : IOEvent, timeout : Time::Span? = nil) : Bool
    if fd < 0
      raise Syscall::Error.new(Errno::EBADF.to_i, operation: "poll", fd: fd, request: events.value.to_u64)
    end
    milliseconds = timeout_to_milliseconds(timeout)
    mask         = events.value | POLL_ERROR | POLL_HUP

    loop do
      pollfd = LibTTYPoll::PollFd.new
      pollfd.fd = fd
      pollfd.events = events.value
      pollfd.revents = 0_i16

      result = LibTTYPoll.poll(pointerof(pollfd), 1_u64, milliseconds)
      if result < 0
        errno = Errno.value.to_i
        next if errno == Errno::EINTR.to_i
        raise Syscall::Error.new(errno, operation: "poll", fd: fd, request: events.value.to_u64)
      end
      return false if result == 0
      if (pollfd.revents & POLL_INVALID) != 0
        raise Syscall::Error.new(Errno::EBADF.to_i, operation: "poll", fd: fd, request: events.value.to_u64)
      end
      return (pollfd.revents & mask) != 0
    end
  end

  private def self.timeout_to_milliseconds(timeout : Time::Span?) : Int32
    return -1 if timeout.nil?
    milliseconds = timeout.total_milliseconds.ceil.to_i64
    raise ArgumentError.new("timeout must be non-negative") if milliseconds < 0
    raise ArgumentError.new("timeout is too large") if milliseconds > Int32::MAX
    milliseconds.to_i32
  end
end
