# examples/demo.cr
require "../src/tty"

shell = ENV["SHELL"]? || "/bin/sh"
size  = TTY::Winsize.from(STDIN) || TTY::Pty::DEFAULT_SIZE

pty = TTY::Pty.new(shell, ["-i"], size: size)

raw = TTY::RawMode.new(STDIN)

Signal::WINCH.trap do
  if current = TTY::Winsize.from(STDIN)
    pty.resize(current) rescue nil
  end
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
    pty.write buffer[0, n]
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
