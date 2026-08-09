# examples/demo.cr
require "./demo_helper"

shell = ENV["SHELL"]? || "/bin/sh"
cols, rows = terminal_size(STDIN.fd)

pty = TTY::Pty.new(shell, ["-i"], cols: cols, rows: rows)

raw = RawMode.new(STDIN.fd)

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
