# bench/macro.cr
require "benchmark"
require "../src/tty"

pty = TTY::PTY.open
fd  = pty.slave_fd

Benchmark.ips do |x|
  x.report("TTY.raw block") { TTY.raw(fd) { } }
  x.report("with_terminal raw") { TTY.with_terminal(fd, raw: true) { } }
  x.report("configure dsl") do
    TTY.configure(fd) do
      raw
    end
  end
  x.report("imperative get/set") do
    original = TTY::Termios.get(fd)
    termios  = original
    termios.make_raw
    termios.set(fd)
    original.set(fd)
  end
end

pty.close
