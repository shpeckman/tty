# examples/winsize.cr
require "../src/tty"

pty = TTY::PTY.open
pty.winsize = TTY::Winsize.new(24_u16, 80_u16)
size = pty.winsize
puts size.rows
puts size.cols
pty.close
