# examples/poller.cr
require "../src/tty"

pty    = TTY::PTY.open
poller = TTY::Poller.new
poller.watch(pty.master_fd, TTY::IOEvent::Readable)
pty.write_slave("x")
event = poller.wait(1000).first
puts poller.backend
puts event.fd == pty.master_fd
puts event.readable?
poller.close
pty.close
