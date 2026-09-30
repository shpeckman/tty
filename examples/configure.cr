# examples/configure.cr
require "../src/tty"

pty = TTY::PTY.open
TTY.configure(pty.slave_fd) do
  raw
  local -EchoE, -EchoK
  input +IStrip
  cc min: 4, time: 10
  baud B38400
  action :now
end
termios = pty.termios
puts termios.local.value
puts termios.input.includes?(TTY::InputFlag::IStrip)
puts termios.baud
puts termios[TTY::ControlChar::Min]
puts termios[TTY::ControlChar::Time]
pty.close
