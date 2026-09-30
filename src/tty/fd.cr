# src/tty/fd.cr
require "./syscall"

module TTY::FD
  def self.status_flags(fd : Int32) : Int32
    Syscall.fcntl(fd, Syscall::F_GETFL)
  end

  def self.descriptor_flags(fd : Int32) : Int32
    Syscall.fcntl(fd, Syscall::F_GETFD)
  end

  def self.nonblocking?(fd : Int32) : Bool
    (status_flags(fd) & Syscall::O_NONBLOCK.to_i32) != 0
  end

  def self.set_nonblocking(fd : Int32, enabled : Bool = true) : Nil
    flags = status_flags(fd)
    if enabled
      flags |= Syscall::O_NONBLOCK.to_i32
    else
      flags &= ~Syscall::O_NONBLOCK.to_i32
    end
    Syscall.fcntl(fd, Syscall::F_SETFL, flags.to_i64)
  end

  def self.cloexec?(fd : Int32) : Bool
    (descriptor_flags(fd) & Syscall::FD_CLOEXEC) != 0
  end

  def self.set_cloexec(fd : Int32, enabled : Bool = true) : Nil
    flags = descriptor_flags(fd)
    if enabled
      flags |= Syscall::FD_CLOEXEC
    else
      flags &= ~Syscall::FD_CLOEXEC
    end
    Syscall.fcntl(fd, Syscall::F_SETFD, flags.to_i64)
  end

  def self.pipe(cloexec : Bool = true) : Tuple(Int32, Int32)
    fds = uninitialized Int32[2]
    flags = cloexec ? Syscall::O_CLOEXEC.to_i32 : 0_i32
    Syscall.pipe2(fds.to_unsafe, flags)
    {fds[0], fds[1]}
  end

  def self.dup3(old_fd : Int32, new_fd : Int32, cloexec : Bool = true) : Nil
    flags = cloexec ? Syscall::O_CLOEXEC.to_i32 : 0_i32
    Syscall.dup3(old_fd, new_fd, flags)
  end

  def self.duplicate_cloexec(fd : Int32, minimum_fd : Int32 = 0) : Int32
    Syscall.fcntl(fd, Syscall::F_DUPFD_CLOEXEC, minimum_fd.to_i64)
  end

  def self.close_range(first : Int32, last : Int32 = Int32::MAX) : Nil
    {% if flag?(:darwin) %}
      raise Error.new("FD.close_range is Linux-only")
    {% else %}
      result = Syscall.raw(Syscall::NR_CLOSE_RANGE, first.to_i64, last.to_i64, 0_i64)
      if result >= 0
        nil
      elsif Syscall.close_range_fallback?(-result.to_i32)
        Syscall.check(Syscall.close_fds_via_procfs(first, last, -1), operation: "close_range")
      else
        Syscall.check(result, operation: "close_range")
      end
    {% end %}
  end

  def self.splice(from : Int32, to : Int32, count : Int, flags : UInt32 = 0_u32) : Int32
    Syscall.splice(from, nil, to, nil, count, flags)
  end

  def self.tee(from : Int32, to : Int32, count : Int, flags : UInt32 = 0_u32) : Int32
    Syscall.tee(from, to, count, flags)
  end

  def self.copy_file_range(from : Int32, to : Int32, count : Int) : Int32
    Syscall.copy_file_range(from, nil, to, nil, count)
  end

  def self.stat(fd : Int32)
    {% if flag?(:darwin) %}
      raise Error.new("FD.stat is not implemented by the Darwin syscall backend")
    {% else %}
      Syscall.fstat(fd)
    {% end %}
  end

  def self.mode(fd : Int32) : UInt32
    stat(fd).mode
  end

  def self.character_device?(fd : Int32) : Bool
    {% if flag?(:darwin) %}
      raise Error.new("FD.character_device? is not implemented by the Darwin syscall backend")
    {% else %}
      (mode(fd) & 0o170000_u32) == 0o020000_u32
    {% end %}
  end

  def self.readv(fd : Int32, buffers : Array(Bytes)) : Int32
    iovecs = buffers.map { |buffer| Syscall::IOVec.new(buffer.to_unsafe, buffer.size.to_u64) }
    Syscall.readv(fd, iovecs.to_unsafe, iovecs.size.to_i32)
  end

  def self.writev(fd : Int32, buffers : Array(Bytes)) : Int32
    iovecs = buffers.map { |buffer| Syscall::IOVec.new(buffer.to_unsafe, buffer.size.to_u64) }
    Syscall.writev(fd, iovecs.to_unsafe, iovecs.size.to_i32)
  end
end
