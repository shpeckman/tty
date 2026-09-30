# src/tty/io.cr
require "./pty"

class TTY::PTY
  class IO < ::IO
    getter io : ::IO::FileDescriptor

    property eof_on_error : Bool

    def initialize(@pty : PTY, eof_on_error : Bool? = nil)
      raise Error.new("an evented IO already exists for this pty") if @pty.evented_io?
      @fd           = @pty.master_fd
      @eof_on_error = eof_on_error.nil? ? @pty.eof_on_error : eof_on_error
      @io           = ::IO::FileDescriptor.new(@fd, close_on_finalize: false)
      @pty.evented_io = self
    end

    def pty : PTY
      @pty
    end

    def fd : Int32
      @fd
    end

    def read(slice : Bytes) : Int32
      raise ::IO::Error.new("Closed stream") if closed?
      @io.read(slice)
    rescue ex : ::IO::Error
      return 0 if @eof_on_error && ex.os_error == Errno::EIO
      raise ex
    end

    def write(slice : Bytes) : Nil
      raise ::IO::Error.new("Closed stream") if closed?
      @io.write(slice)
    end

    def flush : Nil
      @io.flush
    end

    def close : Nil
      return if closed?
      @io.close
      @pty.io_closed
    end

    def closed? : Bool
      @io.closed?
    end

    def read_timeout : Time::Span?
      @io.read_timeout
    end

    def read_timeout=(timeout : Time::Span?) : Time::Span?
      @io.read_timeout = timeout
    end

    def write_timeout : Time::Span?
      @io.write_timeout
    end

    def write_timeout=(timeout : Time::Span?) : Time::Span?
      @io.write_timeout = timeout
    end
  end
end
