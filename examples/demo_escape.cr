# examples/demo_escape.cr
require "./demo_helper"

class EscapeProtocol
  PREFIX = 0x01_u8

  enum State
    Normal
    Awaiting
  end

  record Action, forward : Bytes = Bytes.empty, quit : Bool = false

  @state   = State::Normal
  @logging = false

  def initialize(@fd : Int32, @pty : TTY::Pty)
  end

  def logging? : Bool
    @logging
  end

  def feed(chunk : Bytes) : Action
    sink = IO::Memory.new
    quit = false
    chunk.each do |byte|
      case @state
      in State::Normal
        if byte == PREFIX
          @state = State::Awaiting
        else
          sink.write_byte byte
        end
      in State::Awaiting
        @state = State::Normal
        quit   = true if dispatch(byte, sink)
      end
    end
    Action.new(sink.to_slice.dup, quit)
  end

  private def dispatch(byte : UInt8, sink : IO::Memory) : Bool
    case byte.chr.downcase
    when 'q'
      notice "quit"
      return true
    when 'a'
      sink.write_byte PREFIX
    when 'l'
      sink.write_byte 0x0c_u8
      notice "cleared child screen"
    when 'v'
      @logging = !@logging
      notice "input logging #{@logging ? "on" : "off"}"
    when 'k'
      notice "sent SIGHUP to child"
      @pty.kill
    when '?'
      help
    else
      notice "unknown command: #{printable(byte)}"
    end
    false
  end

  private def printable(byte : UInt8) : String
    byte >= 0x20 && byte < 0x7f ? byte.chr.to_s : sprintf("0x%02x", byte)
  end

  private def help : Nil
    notice "commands: C-a q quit | C-a a literal C-a | " \
           "C-a l clear | C-a v toggle log | C-a k hangup | C-a ? help"
  end

  private def notice(text : String) : Nil
    STDERR.print "\r\n\e[1;33m[demo] #{text}\e[0m\r\n"
    STDERR.flush
  end
end

shell = ENV["SHELL"]? || "/bin/sh"
cols, rows = terminal_size(STDIN.fd)

pty      = TTY::Pty.new(shell, ["-i"], cols: cols, rows: rows)
raw      = RawMode.new(STDIN.fd)
protocol = EscapeProtocol.new(STDIN.fd, pty)

STDERR.print "\r\n\e[1;33m[demo] escape prefix is Ctrl-A. " \
             "Press C-a ? for commands.\e[0m\r\n"
STDERR.flush

Signal::WINCH.trap do
  c, r = terminal_size(STDIN.fd)
  pty.resize(c, r) rescue nil
end

done = Channel(Nil).new

spawn do
  buffer = Bytes.new(4096)
  loop do
    n = pty.master.read(buffer)
    break if n.zero?
    STDOUT.write buffer[0, n]
    STDOUT.flush
  end
rescue IO::Error
ensure
  done.send nil
end

spawn do
  buffer = Bytes.new(4096)
  loop do
    n = STDIN.read(buffer)
    break if n.zero?
    action = protocol.feed(buffer[0, n])
    if protocol.logging? && !action.forward.empty?
      STDERR.print "\r\n\e[2m[log] #{action.forward.hexstring}\e[0m\r\n"
      STDERR.flush
    end
    pty.write action.forward unless action.forward.empty?
    break if action.quit
  end
rescue IO::Error
ensure
  done.send nil
end

done.receive
pty.kill
code = pty.reap
raw.restore

STDOUT.flush
STDERR.puts "\r\n[demo] child exited with #{code.inspect}"
