# src/tty/poller.cr
require "./fd"
require "./readiness"
require "./syscall"

module TTY
  enum PollerBackendKind
    Auto
    Poll
    Epoll
    Kqueue
  end

  struct PollerEvent
    getter fd     : Int32
    getter events : IOEvent

    def initialize(@fd : Int32, @events : IOEvent)
    end

    def readable? : Bool
      events.includes?(IOEvent::Readable)
    end

    def priority? : Bool
      events.includes?(IOEvent::Priority)
    end

    def writable? : Bool
      events.includes?(IOEvent::Writable)
    end

    def error? : Bool
      events.includes?(IOEvent::Error)
    end

    def hangup? : Bool
      events.includes?(IOEvent::HangUp)
    end

    def invalid? : Bool
      events.includes?(IOEvent::Invalid)
    end
  end

  abstract class PollerImplementation
    abstract def watch(fd : Int32, events : IOEvent) : Nil
    abstract def unwatch(fd : Int32) : Nil
    abstract def wait(timeout_ms : Int32 = -1) : Array(PollerEvent)
    abstract def close : Nil
    abstract def closed? : Bool
  end

  class PollPoller < PollerImplementation
    def initialize
      @fds    = Hash(Int32, IOEvent).new
      @closed = false
    end

    def watch(fd : Int32, events : IOEvent) : Nil
      raise Error.new("poller is closed") if closed?
      raise Syscall::Error.new(Syscall::EBADF, operation: "poll", fd: fd) if fd < 0
      @fds[fd] = events
    end

    def unwatch(fd : Int32) : Nil
      @fds.delete(fd)
    end

    def wait(timeout_ms : Int32 = -1) : Array(PollerEvent)
      raise Error.new("poller is closed") if closed?
      raise ArgumentError.new("timeout_ms must be -1 or greater") if timeout_ms < -1
      return [] of PollerEvent if @fds.empty?

      pollfds = @fds.map { |fd, events| PollFd.watch(fd, events) }
      ready   = TTY.poll(pollfds, timeout_ms)
      return [] of PollerEvent if ready == 0

      events = [] of PollerEvent
      pollfds.each do |pollfd|
        next if pollfd.revents == 0
        events << PollerEvent.new(pollfd.fd, IOEvent.new(pollfd.revents))
      end
      events
    end

    def close : Nil
      @closed = true
      @fds.clear
    end

    def closed? : Bool
      @closed
    end
  end

  @[Extern]
  struct EpollEvent
    getter events  : UInt32
    getter fd      : Int32
    getter padding : Int32

    def initialize(@events : UInt32 = 0_u32, @fd : Int32 = 0_i32, @padding : Int32 = 0_i32)
    end
  end

  class EpollPoller < PollerImplementation
    EPOLLIN  = 0x001_u32
    EPOLLPRI = 0x002_u32
    EPOLLOUT = 0x004_u32
    EPOLLERR = 0x008_u32
    EPOLLHUP = 0x010_u32

    def initialize
      @watched = Hash(Int32, IOEvent).new
      @fd      = -1
      {% if flag?(:darwin) %}
        raise Error.new("epoll is Linux-only")
      {% else %}
        @fd = Syscall.epoll_create1(Syscall::O_CLOEXEC.to_i32)
      {% end %}
    end

    def watch(fd : Int32, events : IOEvent) : Nil
      raise Error.new("poller is closed") if closed?
      raise Syscall::Error.new(Syscall::EBADF, operation: "epoll_ctl", fd: fd) if fd < 0
      operation = @watched.has_key?(fd) ? Syscall::EPOLL_CTL_MOD : Syscall::EPOLL_CTL_ADD
      event     = EpollEvent.new(self.class.mask(events), fd)
      Syscall.epoll_ctl(@fd, operation, fd, pointerof(event).as(Pointer(Void)))
      @watched[fd] = events
    end

    def unwatch(fd : Int32) : Nil
      return unless @watched.delete(fd)
      Syscall.epoll_ctl(@fd, Syscall::EPOLL_CTL_DEL, fd)
    end

    def wait(timeout_ms : Int32 = -1) : Array(PollerEvent)
      raise Error.new("poller is closed") if closed?
      raise ArgumentError.new("timeout_ms must be -1 or greater") if timeout_ms < -1
      max_events = {@watched.size, 1}.max
      raw_events = Array(EpollEvent).new(max_events) { EpollEvent.new }

      ready = loop do
        begin
          break Syscall.epoll_wait(@fd, raw_events.to_unsafe.as(Pointer(Void)), max_events, timeout_ms)
        rescue ex : Syscall::Error
          raise ex unless ex.errno == Syscall::EINTR
        end
      end
      return [] of PollerEvent if ready == 0

      raw_events.first(ready).map do |event|
        PollerEvent.new(event.fd, self.class.events(event.events))
      end
    end

    def close : Nil
      return if closed?
      Syscall.close(@fd)
      @fd = -1
      @watched.clear
    end

    def closed? : Bool
      @fd < 0
    end

    def self.mask(events : IOEvent) : UInt32
      mask = 0_u32
      mask |= EPOLLIN if events.includes?(IOEvent::Readable)
      mask |= EPOLLPRI if events.includes?(IOEvent::Priority)
      mask |= EPOLLOUT if events.includes?(IOEvent::Writable)
      mask
    end

    def self.events(mask : UInt32) : IOEvent
      events = IOEvent.new(0_i16)
      events |= IOEvent::Readable if (mask & EPOLLIN) != 0
      events |= IOEvent::Priority if (mask & EPOLLPRI) != 0
      events |= IOEvent::Writable if (mask & EPOLLOUT) != 0
      events |= IOEvent::Error if (mask & EPOLLERR) != 0
      events |= IOEvent::HangUp if (mask & EPOLLHUP) != 0
      events
    end
  end

  @[Extern]
  struct Kevent
    getter ident  : UInt64
    getter filter : Int16
    getter flags  : UInt16
    getter fflags : UInt32
    getter data   : Int64
    getter udata  : UInt64

    def initialize(@ident : UInt64, @filter : Int16, @flags : UInt16, @fflags : UInt32 = 0_u32, @data : Int64 = 0_i64, @udata : UInt64 = 0_u64)
    end
  end

  @[Extern]
  struct KeventTimeout
    def initialize(@seconds : Int64, @nanoseconds : Int64)
    end
  end

  class KqueuePoller < PollerImplementation
    EVFILT_READ  =     -1_i16
    EVFILT_WRITE =     -2_i16
    EV_ADD       = 0x0001_u16
    EV_DELETE    = 0x0002_u16
    EV_ERROR     = 0x4000_u16
    EV_EOF       = 0x8000_u16

    def initialize
      @watched = Hash(Int32, IOEvent).new
      @fd      = -1
      {% if flag?(:darwin) %}
        @fd = Syscall.kqueue
      {% else %}
        raise Error.new("kqueue is Darwin-only")
      {% end %}
    end

    def watch(fd : Int32, events : IOEvent) : Nil
      raise Error.new("poller is closed") if closed?
      raise Syscall::Error.new(Syscall::EBADF, operation: "kevent", fd: fd) if fd < 0
      changes = [] of Kevent
      if events.includes?(IOEvent::Readable) || events.includes?(IOEvent::Priority)
        changes << Kevent.new(fd.to_u64, EVFILT_READ, EV_ADD)
      end
      if events.includes?(IOEvent::Writable)
        changes << Kevent.new(fd.to_u64, EVFILT_WRITE, EV_ADD)
      end
      change(changes)
      @watched[fd] = events
    end

    def unwatch(fd : Int32) : Nil
      events = @watched.delete(fd)
      return unless events
      changes = [] of Kevent
      if events.includes?(IOEvent::Readable) || events.includes?(IOEvent::Priority)
        changes << Kevent.new(fd.to_u64, EVFILT_READ, EV_DELETE)
      end
      if events.includes?(IOEvent::Writable)
        changes << Kevent.new(fd.to_u64, EVFILT_WRITE, EV_DELETE)
      end
      change(changes)
    end

    def wait(timeout_ms : Int32 = -1) : Array(PollerEvent)
      raise Error.new("poller is closed") if closed?
      raise ArgumentError.new("timeout_ms must be -1 or greater") if timeout_ms < -1
      max_events = {@watched.size * 2, 1}.max
      raw_events = Array(Kevent).new(max_events) { Kevent.new(0_u64, 0_i16, 0_u16) }
      timeout    = timeout_ms < 0 ? nil : KeventTimeout.new((timeout_ms // 1000).to_i64, ((timeout_ms % 1000) * 1_000_000).to_i64)

      ready = loop do
        begin
          if timeout
            break Syscall.kevent(@fd, Pointer(Void).null, 0, raw_events.to_unsafe.as(Pointer(Void)), max_events, pointerof(timeout).as(Pointer(Void)))
          else
            break Syscall.kevent(@fd, Pointer(Void).null, 0, raw_events.to_unsafe.as(Pointer(Void)), max_events)
          end
        rescue ex : Syscall::Error
          raise ex unless ex.errno == Syscall::EINTR
        end
      end
      return [] of PollerEvent if ready == 0

      raw_events.first(ready).map do |event|
        flags = IOEvent.new(0_i16)
        if (event.flags & EV_ERROR) != 0
          flags |= IOEvent::Error
        end
        if (event.flags & EV_EOF) != 0
          flags |= IOEvent::HangUp
        end
        if event.filter == EVFILT_READ
          flags |= IOEvent::Readable
        elsif event.filter == EVFILT_WRITE
          flags |= IOEvent::Writable
        end
        PollerEvent.new(event.ident.to_i32, flags)
      end
    end

    def close : Nil
      return if closed?
      Syscall.close(@fd)
      @fd = -1
      @watched.clear
    end

    def closed? : Bool
      @fd < 0
    end

    private def change(changes : Array(Kevent)) : Nil
      return if changes.empty?
      Syscall.kevent(@fd, changes.to_unsafe.as(Pointer(Void)), changes.size, Pointer(Void).null, 0)
    end
  end

  class Poller
    getter backend : PollerBackendKind

    def initialize(backend : PollerBackendKind = PollerBackendKind::Auto)
      @backend = backend == PollerBackendKind::Auto ? self.class.default_backend : backend
      @implementation = case @backend
                        in PollerBackendKind::Poll
                          PollPoller.new
                        in PollerBackendKind::Epoll
                          EpollPoller.new
                        in PollerBackendKind::Kqueue
                          KqueuePoller.new
                        in PollerBackendKind::Auto
                          raise Error.new("unresolved poller backend")
                        end
    end

    def self.default_backend : PollerBackendKind
      {% if flag?(:darwin) %}
        PollerBackendKind::Kqueue
      {% else %}
        PollerBackendKind::Epoll
      {% end %}
    end

    def self.poll : Poller
      new(PollerBackendKind::Poll)
    end

    def watch(fd : Int32, events : IOEvent) : Nil
      @implementation.watch(fd, events)
    end

    def unwatch(fd : Int32) : Nil
      @implementation.unwatch(fd)
    end

    def wait(timeout_ms : Int32 = -1) : Array(PollerEvent)
      @implementation.wait(timeout_ms)
    end

    def close : Nil
      @implementation.close
    end

    def closed? : Bool
      @implementation.closed?
    end
  end
end
