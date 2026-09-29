# src/tty/syscall.cr
@[Link(ldflags: "#{__DIR__}/../ext/tty_syscall.o")]
lib LibTTYSyscall
  fun tty_syscall(nr : UInt64, ...) : Int64
end

module TTY
  module Syscall
    NR_READ   =   0_u64
    NR_WRITE  =   1_u64
    NR_CLOSE  =   3_u64
    NR_IOCTL  =  16_u64
    NR_OPENAT = 257_u64

    AT_FDCWD = -100_i64

    O_RDWR    = 0o0000002_i64
    O_NOCTTY  = 0o0000400_i64
    O_CLOEXEC = 0o2000000_i64

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
        when 11 then "EAGAIN"
        when 12 then "ENOMEM"
        when 13 then "EACCES"
        when 19 then "ENODEV"
        when 22 then "EINVAL"
        when 25 then "ENOTTY"
        else         "ERRNO#{@errno}"
        end
      end
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
  end
end
