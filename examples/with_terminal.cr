# examples/with_terminal.cr
require "../src/tty"

pty = TTY::PTY.open
puts TTY::FD.nonblocking?(pty.slave_fd)
result = TTY.with_terminal(pty.slave_fd, cbreak: true, nonblocking: true) do
  puts TTY::FD.nonblocking?(pty.slave_fd)
  puts TTY::Termios.get(pty.slave_fd).local.includes?(TTY::LocalFlag::ICanon)
  "block value"
end
puts result
puts TTY::FD.nonblocking?(pty.slave_fd)
puts TTY::Termios.get(pty.slave_fd).local.includes?(TTY::LocalFlag::ICanon)
pty.close
