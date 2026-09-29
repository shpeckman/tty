# examples/readiness.cr
require "../src/tty"

pty = TTY::PTY.open
termios = pty.termios
termios.make_raw
pty.termios = termios
TTY.flush(pty.slave_fd)

puts TTY.wait_readable(pty.slave_fd, 0)
pty.write_master("x")
puts TTY.wait_readable(pty.slave_fd, 1000)
buffer = Bytes.new(1)
pty.read_slave(buffer)
puts buffer[0].chr
pty.close
