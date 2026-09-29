# src/tty/syscall.cr
require "./error"
require "./platform"

@[Link(ldflags: "#{__DIR__}/../ext/tty_syscall.o")]
lib LibTTYSyscall
  fun tty_syscall(nr : UInt64, ...) : Int64
end

module TTY
  module Syscall
    {% if flag?(:darwin) %}
      NR_READ        = 0x2000003_u64
      NR_WRITE       = 0x2000004_u64
      NR_CLOSE       = 0x2000006_u64
      NR_WAIT4       = 0x2000007_u64
      NR_FORK        = 0x2000002_u64
      NR_DUP2        = 0x200005A_u64
      NR_IOCTL       = 0x2000036_u64
      NR_SETSID      = 0x2000093_u64
      NR_EXECVE      = 0x200003B_u64
      NR_EXIT_GROUP  = 0x2000001_u64
      NR_OPENAT      = 0x20001CF_u64
      NR_KILL        = 0x2000025_u64
      NR_POLL        = 0x20000E6_u64
      NR_SOCKETPAIR  = 0x2000087_u64
      NR_SIGACTION   = 0x200002E_u64
      NR_SIGPROCMASK = 0x2000030_u64

      AT_FDCWD = -2_i64

      O_RDWR    =       0x2_i64
      O_NOCTTY  =   0x20000_i64
      O_CLOEXEC = 0x1000000_i64

      SIG_SETMASK = 3_i32

      struct Sigaction
        def initialize(@handler : UInt64, @mask : UInt32, @flags : Int32)
        end
      end
    {% else %}
      NR_READ           =   0_u64
      NR_WRITE          =   1_u64
      NR_CLOSE          =   3_u64
      NR_WAIT4          =  61_u64
      NR_FORK           =  57_u64
      NR_DUP2           =  33_u64
      NR_IOCTL          =  16_u64
      NR_SETSID         = 112_u64
      NR_EXECVE         =  59_u64
      NR_EXIT_GROUP     = 231_u64
      NR_OPENAT         = 257_u64
      NR_KILL           =  62_u64
      NR_POLL           =   7_u64
      NR_SOCKETPAIR     =  53_u64
      NR_RT_SIGACTION   =  13_u64
      NR_RT_SIGPROCMASK =  14_u64

      AT_FDCWD = -100_i64

      O_RDWR    = 0o0000002_i64
      O_NOCTTY  = 0o0000400_i64
      O_CLOEXEC = 0o2000000_i64

      SIG_SETMASK = 2_i32
      SIGSET_SIZE = 8_u64

      struct Sigaction
        def initialize(@handler : UInt64, @flags : UInt64, @restorer : UInt64, @mask : UInt64)
        end
      end
    {% end %}

    WNOHANG = 1_i32

    EINTR  =  4_i32
    EBADF  =  9_i32
    ECHILD = 10_i32
    EAGAIN = 11_i32

    AF_UNIX     = 1_i32
    SOCK_STREAM = 1_i32

    SIGKILL =  9_i32
    SIGTERM = 15_i32
    SIGSTOP = 19_i32

    class Error < TTY::Error
      getter errno     : Int32
      getter operation : String
      getter fd        : Int32?
      getter path      : String?
      getter request   : UInt64?

      def initialize(@errno : Int32, @operation : String = "syscall", @fd : Int32? = nil, @path : String? = nil, @request : UInt64? = nil)
        message = String.build do |io|
          io << operation
          io << " fd=" << fd if fd
          io << " path=" << path if path
          io << " request=0x" << request.to_s(16) if request
          io << " failed: "
          io << case errno
          when  1 then "EPERM"
          when  2 then "ENOENT"
          when  4 then "EINTR"
          when  5 then "EIO"
          when  6 then "ENXIO"
          when  9 then "EBADF"
          when 10 then "ECHILD"
          when 11 then "EAGAIN"
          when 12 then "ENOMEM"
          when 13 then "EACCES"
          when 16 then "EBUSY"
          when 19 then "ENODEV"
          when 22 then "EINVAL"
          when 25 then "ENOTTY"
          else         "ERRNO#{errno}"
          end
          io << " (errno " << errno << ')'
        end
        super(message)
      end

      def errno_name : String
        case @errno
        when  1 then "EPERM"
        when  2 then "ENOENT"
        when  4 then "EINTR"
        when  5 then "EIO"
        when  6 then "ENXIO"
        when  9 then "EBADF"
        when 10 then "ECHILD"
        when 11 then "EAGAIN"
        when 12 then "ENOMEM"
        when 13 then "EACCES"
        when 16 then "EBUSY"
        when 19 then "ENODEV"
        when 22 then "EINVAL"
        when 25 then "ENOTTY"
        else         "ERRNO#{@errno}"
        end
      end
    end

    def self.raw(nr : UInt64, a1 : Int64 = 0_i64, a2 : Int64 = 0_i64, a3 : Int64 = 0_i64, a4 : Int64 = 0_i64) : Int64
      LibTTYSyscall.tty_syscall(nr, a1, a2, a3, a4)
    end

    def self.check(ret : Int64, operation : String = "syscall", fd : Int32? = nil, path : String? = nil, request : UInt64? = nil) : Int64
      raise Error.new(-ret.to_i32, operation: operation, fd: fd, path: path, request: request) if ret < 0
      ret
    end

    def self.read(fd : Int32, buffer : Pointer(UInt8), count : Int) : Int32
      check(LibTTYSyscall.tty_syscall(NR_READ, fd, buffer, count.to_u64), operation: "read", fd: fd).to_i32
    end

    def self.write(fd : Int32, buffer : Pointer(UInt8), count : Int) : Int32
      check(LibTTYSyscall.tty_syscall(NR_WRITE, fd, buffer, count.to_u64), operation: "write", fd: fd).to_i32
    end

    def self.write(fd : Int32, data : String) : Int32
      write(fd, data.to_unsafe, data.bytesize)
    end

    def self.close(fd : Int32) : Nil
      check(LibTTYSyscall.tty_syscall(NR_CLOSE, fd), operation: "close", fd: fd)
    end

    def self.ioctl(fd : Int32, request : UInt64, arg : Pointer(T)) : Nil forall T
      check(LibTTYSyscall.tty_syscall(NR_IOCTL, fd, request, arg.as(Pointer(Void))), operation: "ioctl", fd: fd, request: request)
    end

    def self.ioctl(fd : Int32, request : UInt64, arg : Int) : Nil
      check(LibTTYSyscall.tty_syscall(NR_IOCTL, fd, request, arg.to_i64), operation: "ioctl", fd: fd, request: request)
    end

    def self.openat(path : String, flags : Int64) : Int32
      check(LibTTYSyscall.tty_syscall(NR_OPENAT, AT_FDCWD, path.to_unsafe, flags), operation: "openat", path: path).to_i32
    end

    def self.fork : Int32
      check(LibTTYSyscall.tty_syscall(NR_FORK), operation: "fork").to_i32
    end

    def self.dup2(old_fd : Int32, new_fd : Int32) : Nil
      check(LibTTYSyscall.tty_syscall(NR_DUP2, old_fd, new_fd), operation: "dup2", fd: new_fd)
    end

    def self.setsid : Int32
      check(LibTTYSyscall.tty_syscall(NR_SETSID), operation: "setsid").to_i32
    end

    def self.kill(pid : Int32, signal : Int32) : Nil
      check(LibTTYSyscall.tty_syscall(NR_KILL, pid, signal, 0_i64), operation: "kill")
    end

    def self.wait4(pid : Int32, options : Int32 = 0_i32) : Tuple(Int32, Int32)
      status = 0_i32
      result = check(LibTTYSyscall.tty_syscall(NR_WAIT4, pid, pointerof(status), options.to_i64, Pointer(Void).null), operation: "wait4").to_i32
      {result, status}
    end

    def self.poll(fds : Pointer(Void), nfds : UInt64, timeout_ms : Int32) : Int32
      check(LibTTYSyscall.tty_syscall(NR_POLL, fds, nfds, timeout_ms.to_i64), operation: "poll").to_i32
    end

    def self.sleep_ms(timeout_ms : Int32) : Nil
      poll(Pointer(Void).null, 0_u64, timeout_ms)
    rescue ex : Error
      raise ex unless ex.errno == EINTR
    end

    def self.socketpair(domain : Int32, type : Int32, protocol : Int32, fds : Pointer(Int32)) : Nil
      check(LibTTYSyscall.tty_syscall(NR_SOCKETPAIR, domain, type, protocol, fds), operation: "socketpair")
    end

    def self.reset_child_signal_state : Nil
      {% if flag?(:darwin) %}
        action = Sigaction.new(0_u64, 0_u32, 0_i32)
      {% else %}
        action = Sigaction.new(0_u64, 0_u64, 0_u64, 0_u64)
      {% end %}
      (1..31).each do |signal|
        next if signal == SIGKILL || signal == SIGSTOP
        {% if flag?(:darwin) %}
          raw(NR_SIGACTION, signal.to_i64, pointerof(action).address.to_i64, 0_i64)
        {% else %}
          raw(NR_RT_SIGACTION, signal.to_i64, pointerof(action).address.to_i64, 0_i64, SIGSET_SIZE.to_i64)
        {% end %}
      end
      {% if flag?(:darwin) %}
        mask = 0_u32
        raw(NR_SIGPROCMASK, SIG_SETMASK.to_i64, pointerof(mask).address.to_i64, 0_i64)
      {% else %}
        mask = 0_u64
        raw(NR_RT_SIGPROCMASK, SIG_SETMASK.to_i64, pointerof(mask).address.to_i64, 0_i64, SIGSET_SIZE.to_i64)
      {% end %}
    end

    def self.exit_group(code : Int32) : NoReturn
      LibTTYSyscall.tty_syscall(NR_EXIT_GROUP, code)
      LibTTYSyscall.tty_syscall(NR_EXIT_GROUP, code)
      abort
    end
  end
end
