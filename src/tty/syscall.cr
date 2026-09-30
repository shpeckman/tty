# src/tty/syscall.cr
require "./error"
require "./platform"

module TTY::Syscall
  {% if flag?(:darwin) %}
    NR_READ        = 0x2000003_u64
    NR_WRITE       = 0x2000004_u64
    NR_CLOSE       = 0x2000006_u64
    NR_WAIT4       = 0x2000007_u64
    NR_FORK        = 0x2000002_u64
    NR_CHDIR       = 0x200000C_u64
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
    NR_PIPE        = 0x200002A_u64
    NR_FCNTL       = 0x200005C_u64
    NR_READV       = 0x2000078_u64
    NR_WRITEV      = 0x2000079_u64
    NR_KQUEUE      = 0x200016A_u64
    NR_KEVENT      = 0x200016B_u64

    AT_FDCWD = -2_i64

    O_RDWR     =       0x2_i64
    O_NOCTTY   =   0x20000_i64
    O_CLOEXEC  = 0x1000000_i64
    O_NONBLOCK =       0x4_i64

    SIG_SETMASK = 3_i32

    EAGAIN = 35_i32
    ENOSYS = 78_i32

    @[Extern]
    struct Sigaction
      def initialize(@handler : UInt64, @mask : UInt32, @flags : Int32)
      end
    end
  {% else %}
    NR_READ              =   0_u64
    NR_WRITE             =   1_u64
    NR_CLOSE             =   3_u64
    NR_FSTAT             =   5_u64
    NR_POLL              =   7_u64
    NR_IOCTL             =  16_u64
    NR_READV             =  19_u64
    NR_WRITEV            =  20_u64
    NR_DUP2              =  33_u64
    NR_GETPID            =  39_u64
    NR_FORK              =  57_u64
    NR_EXECVE            =  59_u64
    NR_WAIT4             =  61_u64
    NR_KILL              =  62_u64
    NR_UNAME             =  63_u64
    NR_FCNTL             =  72_u64
    NR_CHDIR             =  80_u64
    NR_SETPGID           = 109_u64
    NR_SETSID            = 112_u64
    NR_GETPGID           = 121_u64
    NR_EXIT_GROUP        = 231_u64
    NR_EPOLL_WAIT        = 232_u64
    NR_EPOLL_CTL         = 233_u64
    NR_OPENAT            = 257_u64
    NR_EPOLL_CREATE1     = 291_u64
    NR_DUP3              = 292_u64
    NR_PIPE2             = 293_u64
    NR_WAITID            = 247_u64
    NR_PIDFD_SEND_SIGNAL = 424_u64
    NR_PIDFD_OPEN        = 434_u64
    NR_CLOSE_RANGE       = 436_u64
    NR_SOCKETPAIR        =  53_u64
    NR_RT_SIGACTION      =  13_u64
    NR_RT_SIGPROCMASK    =  14_u64
    NR_SPLICE            = 275_u64
    NR_TEE               = 276_u64
    NR_GETDENTS64        = 217_u64
    NR_COPY_FILE_RANGE   = 326_u64

    AT_FDCWD = -100_i64

    O_RDONLY    = 0o0000000_i64
    O_RDWR      = 0o0000002_i64
    O_NOCTTY    = 0o0000400_i64
    O_NONBLOCK  = 0o0004000_i64
    O_CLOEXEC   = 0o2000000_i64
    O_DIRECTORY =  0o200000_i64

    EAGAIN = 11_i32
    ENOSYS = 38_i32

    SIG_SETMASK = 2_i32
    SIGSET_SIZE = 8_u64

    SPLICE_F_MOVE     = 1_u32
    SPLICE_F_NONBLOCK = 2_u32
    SPLICE_F_MORE     = 4_u32
    SPLICE_F_GIFT     = 8_u32

    @[Extern]
    struct Sigaction
      def initialize(@handler : UInt64, @flags : UInt64, @restorer : UInt64, @mask : UInt64)
      end
    end
  {% end %}

  F_GETFD         =    1_i32
  F_SETFD         =    2_i32
  F_GETFL         =    3_i32
  F_SETFL         =    4_i32
  F_DUPFD_CLOEXEC = 1030_i32
  FD_CLOEXEC      =    1_i32

  WNOHANG    =         1_i32
  WUNTRACED  =         2_i32
  WSTOPPED   =         2_i32
  WEXITED    =         4_i32
  WCONTINUED =         8_i32
  WNOWAIT    = 0x1000000_i32

  P_ALL   = 0_i32
  P_PID   = 1_i32
  P_PGID  = 2_i32
  P_PIDFD = 3_i32

  CLD_EXITED    = 1_i32
  CLD_KILLED    = 2_i32
  CLD_DUMPED    = 3_i32
  CLD_TRAPPED   = 4_i32
  CLD_STOPPED   = 5_i32
  CLD_CONTINUED = 6_i32

  EPERM  =  1_i32
  ENOENT =  2_i32
  EINTR  =  4_i32
  EIO    =  5_i32
  ENXIO  =  6_i32
  EBADF  =  9_i32
  ECHILD = 10_i32
  ENOMEM = 12_i32
  EACCES = 13_i32
  EBUSY  = 16_i32
  EEXIST = 17_i32
  ENODEV = 19_i32
  EINVAL = 22_i32
  ENOTTY = 25_i32
  EPIPE  = 32_i32

  AF_UNIX     = 1_i32
  SOCK_STREAM = 1_i32

  SIGKILL =  9_i32
  SIGTERM = 15_i32
  SIGCONT = 18_i32
  SIGSTOP = 19_i32

  EPOLL_CTL_ADD = 1_i32
  EPOLL_CTL_DEL = 2_i32
  EPOLL_CTL_MOD = 3_i32

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
        io << self.class.errno_name_for(errno)
        io << " (errno " << errno << ')'
      end
      super(message)
    end

    def errno_name : String
      self.class.errno_name_for(@errno)
    end

    def self.errno_name_for(errno : Int32) : String
      case errno
      when EPERM  then "EPERM"
      when ENOENT then "ENOENT"
      when EINTR  then "EINTR"
      when EIO    then "EIO"
      when ENXIO  then "ENXIO"
      when EBADF  then "EBADF"
      when ECHILD then "ECHILD"
      when EAGAIN then "EAGAIN"
      when ENOMEM then "ENOMEM"
      when EACCES then "EACCES"
      when EBUSY  then "EBUSY"
      when EEXIST then "EEXIST"
      when ENODEV then "ENODEV"
      when EINVAL then "EINVAL"
      when ENOTTY then "ENOTTY"
      when EPIPE  then "EPIPE"
      when ENOSYS then "ENOSYS"
      else             "ERRNO#{errno}"
      end
    end
  end

  @[Extern]
  struct IOVec
    getter base   : Pointer(UInt8)
    getter length : UInt64

    def initialize(@base : Pointer(UInt8), @length : UInt64)
    end
  end

  {% unless flag?(:darwin) %}
    @[Extern]
    struct Stat
      getter dev : UInt64
      getter ino : UInt64
      getter nlink : UInt64
      getter mode : UInt32
      getter uid : UInt32
      getter gid : UInt32
      @pad0 : Int32
      getter rdev : UInt64
      getter size : Int64
      getter blksize : Int64
      getter blocks : Int64
      getter atime : Int64
      getter atime_nsec : Int64
      getter mtime : Int64
      getter mtime_nsec : Int64
      getter ctime : Int64
      getter ctime_nsec : Int64
      @unused : StaticArray(Int64, 3)

      def initialize
        @dev = 0_u64
        @ino = 0_u64
        @nlink = 0_u64
        @mode = 0_u32
        @uid = 0_u32
        @gid = 0_u32
        @pad0 = 0_i32
        @rdev = 0_u64
        @size = 0_i64
        @blksize = 0_i64
        @blocks = 0_i64
        @atime = 0_i64
        @atime_nsec = 0_i64
        @mtime = 0_i64
        @mtime_nsec = 0_i64
        @ctime = 0_i64
        @ctime_nsec = 0_i64
        @unused = StaticArray(Int64, 3).new(0_i64)
      end
    end

    @[Extern]
    struct Siginfo
      getter signo : Int32
      getter errno : Int32
      getter code : Int32
      @pad0 : Int32
      getter pid : Int32
      getter uid : UInt32
      getter status : Int32
      getter utime : Int64
      getter stime : Int64
      @padding : StaticArray(UInt8, 80)

      def initialize
        @signo = 0_i32
        @errno = 0_i32
        @code = 0_i32
        @pad0 = 0_i32
        @pid = 0_i32
        @uid = 0_u32
        @status = 0_i32
        @utime = 0_i64
        @stime = 0_i64
        @padding = StaticArray(UInt8, 80).new(0_u8)
      end
    end
  {% end %}

  def self.raw(nr : UInt64, a1 : Int64 = 0_i64, a2 : Int64 = 0_i64, a3 : Int64 = 0_i64, a4 : Int64 = 0_i64, a5 : Int64 = 0_i64, a6 : Int64 = 0_i64) : Int64
    {% if flag?(:x86_64) %}
      result = 0_i64
      asm("syscall" : "={rax}"(result) : "{rax}"(nr), "{rdi}"(a1), "{rsi}"(a2), "{rdx}"(a3), "{r10}"(a4), "{r8}"(a5), "{r9}"(a6) : "rcx", "r11", "memory" : "volatile")
      result
    {% else %}
        {% raise "TTY requires an x86_64 target" %}
      {% end %}
  end

  def self.check(ret : Int64, operation : String = "syscall", fd : Int32? = nil, path : String? = nil, request : UInt64? = nil) : Int64
    raise Error.new(-ret.to_i32, operation: operation, fd: fd, path: path, request: request) if ret < 0
    ret
  end

  def self.arg(value : Int) : Int64
    value.to_i64
  end

  def self.arg(value : Pointer(T)) : Int64 forall T
    value.address.to_i64
  end

  def self.arg(value : Nil) : Int64
    0_i64
  end

  def self.arg(value : String) : Int64
    value.to_unsafe.address.to_i64
  end

  macro def_syscall(name, nr, *args, returns = Int32, generic = nil, op = nil, fd = nil, path = nil, request = nil, linux_only = false, darwin_only = false)
    {% if linux_only && darwin_only %}
      {% raise "def_syscall accepts linux_only or darwin_only, not both" %}
    {% end %}
    {% operation = op || name.id.stringify %}
    {% fd_report = fd %}
    {% unless fd_report %}
      {% for argument in args %}
        {% if argument.var.stringify == "fd" %}
          {% fd_report = argument.var %}
        {% end %}
      {% end %}
    {% end %}
    def self.{{name.id}}({% for argument, index in args %}{{argument}}{% if index < args.size - 1 %}, {% end %}{% end %}) : {{returns}}{% if generic %} forall {{generic}}{% end %}
      {% if linux_only && flag?(:darwin) %}
        raise TTY::Error.new({{name.id.stringify + " is Linux-only"}})
      {% elsif darwin_only && !flag?(:darwin) %}
        raise TTY::Error.new({{name.id.stringify + " is Darwin-only"}})
      {% else %}
        {% if returns.stringify == "Nil" %}
          check(raw({{nr}}{% for argument in args %}, arg({{argument.var}}){% end %}), operation: {{operation}}{% if fd_report %}, fd: {{fd_report}}{% end %}{% if path %}, path: {{path}}{% end %}{% if request %}, request: {{request}}{% end %})
        {% else %}
          check(raw({{nr}}{% for argument in args %}, arg({{argument.var}}){% end %}), operation: {{operation}}{% if fd_report %}, fd: {{fd_report}}{% end %}{% if path %}, path: {{path}}{% end %}{% if request %}, request: {{request}}{% end %}).to_i32
        {% end %}
      {% end %}
    end
  end

  def_syscall read, NR_READ, fd : Int32, buffer : Pointer(UInt8), count : Int

  def_syscall write, NR_WRITE, fd : Int32, buffer : Pointer(UInt8), count : Int

  def self.write(fd : Int32, data : String) : Int32
    write(fd, data.to_unsafe, data.bytesize)
  end

  def self.write(fd : Int32, data : Bytes) : Int32
    write(fd, data.to_unsafe, data.size)
  end

  def_syscall readv, NR_READV, fd : Int32, iovecs : Pointer(IOVec), count : Int32

  def_syscall writev, NR_WRITEV, fd : Int32, iovecs : Pointer(IOVec), count : Int32

  def_syscall close, NR_CLOSE, fd : Int32, returns: Nil

  def_syscall fcntl, NR_FCNTL, fd : Int32, command : Int32, argument : Int64 = 0_i64

  def self.fstat(fd : Int32)
    {% if flag?(:darwin) %}
      raise TTY::Error.new("fstat is not implemented by the Darwin syscall backend")
    {% else %}
      stat = Stat.new
      check(raw(NR_FSTAT, fd.to_i64, pointerof(stat).address.to_i64), operation: "fstat", fd: fd)
      stat
    {% end %}
  end

  def_syscall ioctl_result, NR_IOCTL, fd : Int32, request : UInt64, arg : Pointer(T), generic: T, op: "ioctl", request: request

  def_syscall ioctl_result, NR_IOCTL, fd : Int32, request : UInt64, arg : Int, op: "ioctl", request: request

  def self.ioctl(fd : Int32, request : UInt64, arg : Pointer(T)) : Nil forall T
    ioctl_result(fd, request, arg)
  end

  def self.ioctl(fd : Int32, request : UInt64, arg : Int) : Nil
    ioctl_result(fd, request, arg)
  end

  def self.openat(path : String, flags : Int64) : Int32
    check(raw(NR_OPENAT, AT_FDCWD, path.to_unsafe.address.to_i64, flags), operation: "openat", path: path).to_i32
  end

  def self.pipe2(fds : Pointer(Int32), flags : Int32 = 0_i32) : Nil
    {% if flag?(:darwin) %}
      check(raw(NR_PIPE, fds.address.to_i64), operation: "pipe")
      if flags != 0
        fcntl(fds[0], F_SETFD, FD_CLOEXEC.to_i64)
        fcntl(fds[1], F_SETFD, FD_CLOEXEC.to_i64)
      end
    {% else %}
      check(raw(NR_PIPE2, fds.address.to_i64, flags.to_i64), operation: "pipe2")
    {% end %}
  end

  def_syscall dup2, NR_DUP2, old_fd : Int32, new_fd : Int32, returns: Nil, fd: new_fd

  def_syscall dup3, NR_DUP3, old_fd : Int32, new_fd : Int32, flags : Int32 = 0_i32, returns: Nil, fd: new_fd, linux_only: true

  def_syscall chdir, NR_CHDIR, path : String, returns: Nil, path: path

  def_syscall fork, NR_FORK

  def self.execve(path : String, argv : Pointer(Pointer(UInt8)), envp : Pointer(Pointer(UInt8))) : NoReturn
    ret = raw(NR_EXECVE, path.to_unsafe.address.to_i64, argv.address.to_i64, envp.address.to_i64)
    raise Error.new(-ret.to_i32, operation: "execve", path: path)
  end

  def_syscall getpid, NR_GETPID, linux_only: true

  def_syscall getpgid, NR_GETPGID, pid : Int32, linux_only: true

  def_syscall setpgid, NR_SETPGID, pid : Int32, pgrp : Int32, returns: Nil, linux_only: true

  def_syscall setsid, NR_SETSID

  def_syscall kill, NR_KILL, pid : Int32, signal : Int32, returns: Nil

  def self.killpg(pgrp : Int32, signal : Int32) : Nil
    kill(-pgrp, signal)
  end

  def self.wait4(pid : Int32, options : Int32 = 0_i32) : Tuple(Int32, Int32)
    status = 0_i32
    result = check(raw(NR_WAIT4, pid.to_i64, pointerof(status).address.to_i64, options.to_i64, Pointer(Void).null.address.to_i64), operation: "wait4").to_i32
    {result, status}
  end

  def self.waitid(id_type : Int32, id : Int32, options : Int32)
    {% if flag?(:darwin) %}
      raise TTY::Error.new("waitid is not implemented by the Darwin syscall backend")
    {% else %}
      info = Siginfo.new
      check(raw(NR_WAITID, id_type.to_i64, id.to_i64, pointerof(info).address.to_i64, options.to_i64, Pointer(Void).null.address.to_i64), operation: "waitid")
      info
    {% end %}
  end

  def_syscall pidfd_open, NR_PIDFD_OPEN, pid : Int32, flags : UInt32 = 0_u32, linux_only: true

  def self.pidfd_send_signal(pidfd : Int32, signal : Int32, flags : UInt32 = 0_u32) : Nil
    {% if flag?(:darwin) %}
      raise TTY::Error.new("pidfd_send_signal is Linux-only")
    {% else %}
      check(raw(NR_PIDFD_SEND_SIGNAL, pidfd.to_i64, signal.to_i64, Pointer(Void).null.address.to_i64, flags.to_i64), operation: "pidfd_send_signal", fd: pidfd)
    {% end %}
  end

  def_syscall poll, NR_POLL, fds : Pointer(Void), nfds : UInt64, timeout_ms : Int32

  def self.sleep_ms(timeout_ms : Int32) : Nil
    poll(Pointer(Void).null, 0_u64, timeout_ms)
  rescue ex : Error
    raise ex unless ex.errno == EINTR
  end

  def_syscall socketpair, NR_SOCKETPAIR, domain : Int32, type : Int32, protocol : Int32, fds : Pointer(Int32), returns: Nil

  def_syscall close_range, NR_CLOSE_RANGE, first : Int32, last : Int32, flags : UInt32 = 0_u32, returns: Nil, linux_only: true

  def self.close_range_fallback?(errno : Int32) : Bool
    errno == ENOSYS || errno == EPERM || errno == EINVAL
  end

  def self.close_fds_from(first : Int32, except : Int32) : Int64
    {% if flag?(:darwin) %}
      -ENOSYS.to_i64
    {% else %}
      result = raw(NR_CLOSE_RANGE, first.to_i64, Int32::MAX.to_i64, 0_i64)
      return 0_i64 if result >= 0
      return result unless close_range_fallback?(-result.to_i32)
      close_fds_via_procfs(first, Int32::MAX, except)
    {% end %}
  end

  def self.close_fds_via_procfs(first : Int32, last : Int32, except : Int32) : Int64
    {% if flag?(:darwin) %}
      -ENOSYS.to_i64
    {% else %}
      dir = raw(NR_OPENAT, AT_FDCWD, "/proc/self/fd".to_unsafe.address.to_i64, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
      return dir if dir < 0
      dir_fd = dir.to_i32
      buffer = uninitialized UInt8[2048]
      failure = 0_i64
      loop do
        bytes = raw(NR_GETDENTS64, dir.to_i64, buffer.to_unsafe.address.to_i64, buffer.size.to_i64)
        break if bytes <= 0
        position = 0_i64
        while position < bytes
          record_length = (buffer.to_unsafe + position + 16).as(Pointer(UInt16)).value.to_i64
          break if record_length == 0
          name = buffer.to_unsafe + position + 19
          fd = 0_i32
          digits = false
          while name.value >= 48_u8 && name.value <= 57_u8
            fd = fd &* 10 &+ (name.value &- 48_u8).to_i32
            digits = true
            name += 1
          end
          if digits && fd >= first && fd <= last && fd != except && fd != dir_fd
            result = raw(NR_CLOSE, fd.to_i64)
            failure = result if failure == 0_i64 && result < 0
          end
          position += record_length
        end
      end
      raw(NR_CLOSE, dir)
      failure
    {% end %}
  end

  def self.splice(fd_in : Int32, offset_in : Int64?, fd_out : Int32, offset_out : Int64?, count : Int, flags : UInt32 = 0_u32) : Int32
    {% if flag?(:darwin) %}
      raise TTY::Error.new("splice is Linux-only")
    {% else %}
      in_value = offset_in || 0_i64
      out_value = offset_out || 0_i64
      in_pointer = offset_in ? pointerof(in_value) : Pointer(Int64).null
      out_pointer = offset_out ? pointerof(out_value) : Pointer(Int64).null
      check(raw(NR_SPLICE, fd_in.to_i64, in_pointer.address.to_i64, fd_out.to_i64, out_pointer.address.to_i64, count.to_i64, flags.to_i64), operation: "splice").to_i32
    {% end %}
  end

  def_syscall tee, NR_TEE, fd_in : Int32, fd_out : Int32, count : Int, flags : UInt32 = 0_u32, linux_only: true

  def self.copy_file_range(fd_in : Int32, offset_in : Int64?, fd_out : Int32, offset_out : Int64?, count : Int, flags : UInt32 = 0_u32) : Int32
    {% if flag?(:darwin) %}
      raise TTY::Error.new("copy_file_range is Linux-only")
    {% else %}
      in_value = offset_in || 0_i64
      out_value = offset_out || 0_i64
      in_pointer = offset_in ? pointerof(in_value) : Pointer(Int64).null
      out_pointer = offset_out ? pointerof(out_value) : Pointer(Int64).null
      check(raw(NR_COPY_FILE_RANGE, fd_in.to_i64, in_pointer.address.to_i64, fd_out.to_i64, out_pointer.address.to_i64, count.to_i64, flags.to_i64), operation: "copy_file_range").to_i32
    {% end %}
  end

  def_syscall epoll_create1, NR_EPOLL_CREATE1, flags : Int32 = 0_i32, linux_only: true

  def_syscall epoll_ctl, NR_EPOLL_CTL, epfd : Int32, operation : Int32, fd : Int32, event : Pointer(Void)? = nil, returns: Nil, linux_only: true

  def_syscall epoll_wait, NR_EPOLL_WAIT, epfd : Int32, events : Pointer(Void), max_events : Int32, timeout_ms : Int32, fd: epfd, linux_only: true

  def_syscall kqueue, NR_KQUEUE, darwin_only: true

  def_syscall kevent, NR_KEVENT, kq : Int32, changes : Pointer(Void), change_count : Int32, events : Pointer(Void), event_count : Int32, timeout : Pointer(Void)? = nil, fd: kq, darwin_only: true

  def self.reset_child_signal_state : Nil
    {% if flag?(:darwin) %}
      action = Sigaction.new(0_u64, 0_u32, 0_i32)
      (1..31).each do |signal|
        next if signal == SIGKILL || signal == SIGSTOP
        raw(NR_SIGACTION, signal.to_i64, pointerof(action).address.to_i64, 0_i64)
      end
      mask = 0_u32
      raw(NR_SIGPROCMASK, SIG_SETMASK.to_i64, pointerof(mask).address.to_i64, 0_i64)
    {% else %}
      action = Sigaction.new(0_u64, 0_u64, 0_u64, 0_u64)
      (1..64).each do |signal|
        next if signal == SIGKILL || signal == SIGSTOP || signal == 32 || signal == 33
        raw(NR_RT_SIGACTION, signal.to_i64, pointerof(action).address.to_i64, 0_i64, SIGSET_SIZE.to_i64)
      end
      mask = 0_u64
      raw(NR_RT_SIGPROCMASK, SIG_SETMASK.to_i64, pointerof(mask).address.to_i64, 0_i64, SIGSET_SIZE.to_i64)
    {% end %}
  end

  def self.exit_group(code : Int32) : NoReturn
    raw(NR_EXIT_GROUP, code.to_i64)
    raw(NR_EXIT_GROUP, code.to_i64)
    abort
  end
end
