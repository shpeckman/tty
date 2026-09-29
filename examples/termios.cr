# examples/termios.cr
require "../src/tty"

pty      = TTY::PTY.open
original = pty.termios
raw      = original
raw.make_raw
pty.termios = raw
puts pty.termios.input.value
puts pty.termios.local.value
pty.termios = original
pty.close
