# src/tty/syscall.cr
require "./platform"

@[Link(ldflags: "#{__DIR__}/../ext/tty_syscall.o")]
lib LibTTYSyscall
  fun tty_syscall(nr : UInt64, ...) : Int64
end

module TTY
  module Syscall
    {% if flag?(:darwin) %}
      NR_READ       = 0x2000003_u64
      NR_WRITE      = 0x2000004_u64
      NR_CLOSE      = 0x2000006_u64
      NR_WAIT4      = 0x2000007_u64
      NR_FORK       = 0x2000002_u64
      NR_DUP2       = 0x200005A_u64
      NR_IOCTL      = 0x2000036_u64
      NR_SETSID     = 0x2000093_u64
      NR_EXECVE     = 0x200003B_u64
      NR_EXIT_GROUP = 0x2000001_u64
      NR_OPENAT     = 0x20001CF_u64

      AT_FDCWD = -2_i64

      O_RDWR    =       0x2_i64
      O_NOCTTY  =   0x20000_i64
      O_CLOEXEC = 0x1000000_i64
    {% else %}
      NR_READ       =   0_u64
      NR_WRITE      =   1_u64
      NR_CLOSE      =   3_u64
      NR_WAIT4      =  61_u64
      NR_FORK       =  57_u64
      NR_DUP2       =  33_u64
      NR_IOCTL      =  16_u64
      NR_SETSID     = 112_u64
      NR_EXECVE     =  59_u64
      NR_EXIT_GROUP = 231_u64
      NR_OPENAT     = 257_u64

      AT_FDCWD = -100_i64

      O_RDWR    = 0o0000002_i64
      O_NOCTTY  = 0o0000400_i64
      O_CLOEXEC = 0o2000000_i64
    {% end %}

    class Error < Exception
      getter errno : Int32

      def initialize(@errno : Int32)
        super("#{errno_name} (errno #{@errno})")
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

    def self.check(ret : Int64) : Int64
      raise Error.new(-ret.to_i32) if ret < 0
      ret
    end

    def self.read(fd : Int32, buffer : Pointer(UInt8), count : Int) : Int32
      check(LibTTYSyscall.tty_syscall(NR_READ, fd, buffer, count.to_u64)).to_i32
    end

    def self.write(fd : Int32, buffer : Pointer(UInt8), count : Int) : Int32
      check(LibTTYSyscall.tty_syscall(NR_WRITE, fd, buffer, count.to_u64)).to_i32
    end

    def self.write(fd : Int32, data : String) : Int32
      write(fd, data.to_unsafe, data.bytesize)
    end

    def self.close(fd : Int32) : Nil
      check(LibTTYSyscall.tty_syscall(NR_CLOSE, fd))
    end

    def self.ioctl(fd : Int32, request : UInt64, arg : Pointer(T)) : Nil forall T
      check(LibTTYSyscall.tty_syscall(NR_IOCTL, fd, request, arg.as(Pointer(Void))))
    end

    def self.ioctl(fd : Int32, request : UInt64, arg : Int) : Nil
      check(LibTTYSyscall.tty_syscall(NR_IOCTL, fd, request, arg.to_i64))
    end

    def self.openat(path : String, flags : Int64) : Int32
      check(LibTTYSyscall.tty_syscall(NR_OPENAT, AT_FDCWD, path.to_unsafe, flags)).to_i32
    end

    def self.fork : Int32
      check(LibTTYSyscall.tty_syscall(NR_FORK)).to_i32
    end

    def self.dup2(old_fd : Int32, new_fd : Int32) : Nil
      check(LibTTYSyscall.tty_syscall(NR_DUP2, old_fd, new_fd))
    end

    def self.setsid : Int32
      check(LibTTYSyscall.tty_syscall(NR_SETSID)).to_i32
    end

    def self.wait4(pid : Int32) : Tuple(Int32, Int32)
      status = 0_i32
      result = check(LibTTYSyscall.tty_syscall(NR_WAIT4, pid, pointerof(status), 0_i64, Pointer(Void).null)).to_i32
      {result, status}
    end

    def self.exit_group(code : Int32) : NoReturn
      LibTTYSyscall.tty_syscall(NR_EXIT_GROUP, code)
      LibTTYSyscall.tty_syscall(NR_EXIT_GROUP, code)
      abort
    end
  end
end
