# src/tty/conversions.cr
module TTY
  alias Descriptor = Int32 | ::IO::FileDescriptor
  alias Timeout = Int32 | Time::Span | Nil
  alias SignalValue = Int32 | ::Signal

  def self.fd_of(fd : Int32) : Int32
    fd
  end

  def self.fd_of(io : ::IO::FileDescriptor) : Int32
    io.fd
  end

  def self.timeout_ms(timeout : Nil) : Int32
    -1
  end

  def self.timeout_ms(timeout : Int32) : Int32
    raise ArgumentError.new("timeout must be -1 or greater") if timeout < -1
    timeout
  end

  def self.timeout_ms(timeout : Time::Span) : Int32
    raise ArgumentError.new("timeout must be -1 or greater") if timeout.negative?
    milliseconds = timeout.total_milliseconds.ceil
    milliseconds >= Int32::MAX ? Int32::MAX : milliseconds.to_i32
  end

  def self.signal_number(signal : Int32) : Int32
    signal
  end

  def self.signal_number(signal : ::Signal) : Int32
    signal.value
  end
end
