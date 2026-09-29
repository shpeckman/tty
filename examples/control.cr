# examples/control.cr
require "../src/tty"

pty     = TTY::PTY.open
termios = pty.termios
termios.make_raw
pty.termios = termios
TTY.flush(pty.slave_fd)

pty.write_master("abc")
TTY.wait_readable(pty.slave_fd, 1000)
puts TTY.pending_input(pty.slave_fd)
buffer = Bytes.new(3)
pty.read_slave(buffer)
puts TTY.pending_input(pty.slave_fd)
puts TTY.pending_output(pty.master_fd)
pty.close
