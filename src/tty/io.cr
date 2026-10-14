# src/tty/io.cr
require "./conversions"
require "./pty"

class TTY::PTY
  class IO < ::IO
    LINE_ENDING = "\r"
    CHUNK_SIZE  = 4096

    getter io : ::IO::FileDescriptor

    property eof_on_error : Bool

    def initialize(@pty : PTY, eof_on_error : Bool? = nil)
      raise Error.new("an evented IO already exists for this pty") if @pty.evented_io
      @fd           = @pty.master_fd
      @eof_on_error = eof_on_error.nil? ? @pty.eof_on_error : eof_on_error
      @io           = ::IO::FileDescriptor.new(@fd, close_on_finalize: false)
      @io.sync = true
      @unread = Bytes.empty
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
      return fill(slice) if @unread.empty?
      count = Math.min(slice.size, @unread.size)
      slice.copy_from(@unread[0, count])
      @unread += count
      count
    end

    def write(slice : Bytes) : Nil
      raise ::IO::Error.new("Closed stream") if closed?
      @io.write(slice)
    end

    def flush : Nil
      @io.flush
    end

    def sync? : Bool
      @io.sync?
    end

    def sync=(sync : Bool) : Bool
      @io.sync = sync
    end

    def expect(pattern : Regex | String, timeout : Timeout = nil) : Regex::MatchData
      raise ::IO::Error.new("Closed stream") if closed?
      regex    = matcher(pattern)
      limit    = TTY.timeout_ms(timeout)
      deadline = limit < 0 ? nil : now + limit.milliseconds
      received = ::IO::Memory.new
      received.write(@unread)
      @unread = Bytes.empty
      chunk   = Bytes.new(CHUNK_SIZE)
      saved   = @io.read_timeout
      begin
        loop do
          if match = regex.match(String.new(received.to_slice))
            @unread = received.to_slice[match.byte_end(0)..].dup
            return match
          end
          if deadline
            remaining = deadline - now
            raise ::IO::TimeoutError.new("expect timed out waiting for #{regex.inspect}") unless remaining.positive?
            @io.read_timeout = remaining
          end
          count = fill(chunk)
          raise ::IO::EOFError.new("end of stream while waiting for #{regex.inspect}") if count == 0
          received.write(chunk[0, count])
        end
      rescue ex
        @unread = received.to_slice.dup
        raise ex
      ensure
        @io.read_timeout = saved
      end
    end

    def send_line(line : String = "") : Nil
      write(line.to_slice)
      write(LINE_ENDING.to_slice)
      flush
    end

    def close : Nil
      return if closed?
      @io.close
      @unread = Bytes.empty
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

    private def now
      {% if compare_versions(Crystal::VERSION, "1.19.0-0") >= 0 %}
        Time.instant
      {% else %}
        Time.monotonic
      {% end %}
    end

    private def fill(slice : Bytes) : Int32
      @io.read(slice)
    rescue ex : ::IO::Error
      return 0 if @eof_on_error && ex.os_error == Errno::EIO
      raise ex
    end

    private def matcher(pattern : String) : Regex
      Regex.new(Regex.escape(pattern), Regex::CompileOptions::MATCH_INVALID_UTF)
    end

    private def matcher(pattern : Regex) : Regex
      Regex.new(pattern.source, pattern.options | Regex::CompileOptions::MATCH_INVALID_UTF)
    end
  end
end
