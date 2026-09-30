# benchmarks/syscall.cr
require "benchmark"
require "../src/tty"

read_fd, write_fd = TTY::FD.pipe

Benchmark.ips do |x|
  x.report("getpid") { TTY::Syscall.getpid }
  x.report("fcntl F_GETFL") { TTY::Syscall.fcntl(read_fd, TTY::Syscall::F_GETFL) }
  x.report("poll zero-timeout") { TTY::Syscall.sleep_ms(0) }
  x.report("pipe round-trip 64B") do
    TTY::Syscall.write(write_fd, "x" * 64)
    buffer = Bytes.new(64)
    TTY::Syscall.read(read_fd, buffer.to_unsafe, buffer.size)
  end
end

TTY::Syscall.close(read_fd)
TTY::Syscall.close(write_fd)
