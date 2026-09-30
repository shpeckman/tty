# benchmarks/poller.cr
require "benchmark"
require "../src/tty"

idle = Array(Tuple(Int32, Int32)).new(64) { TTY::FD.pipe }
read_fd, write_fd = TTY::FD.pipe

poller = TTY::Poller.new
idle.each { |(r, _)| poller.watch(r, TTY::IOEvent::Readable) }
poller.watch(read_fd, TTY::IOEvent::Readable)

Benchmark.ips do |x|
  x.report("poller 65 fds one ready") do
    TTY::Syscall.write(write_fd, "x")
    events = poller.wait(1000)
    raise "no events" if events.empty?
    buffer = Bytes.new(1)
    TTY::Syscall.read(events[0].fd, buffer.to_unsafe, 1)
  end
end

poller.close
idle.each { |(r, w)| TTY::Syscall.close(r); TTY::Syscall.close(w) }
TTY::Syscall.close(read_fd)
TTY::Syscall.close(write_fd)
