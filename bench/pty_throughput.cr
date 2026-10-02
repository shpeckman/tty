# bench/pty_throughput.cr
require "benchmark"
require "../src/tty"

pty = TTY::PTY.open

raw = pty.termios
raw.make_raw
pty.termios = raw

payload  = Bytes.new(1024) { |i| (i % 26 + 97).to_u8 }
received = Bytes.new(1024)

Benchmark.ips do |x|
  x.report("pty master->slave 1KiB") do
    TTY::Syscall.write(pty.master_fd, payload)
    total = 0
    while total < payload.size
      total += pty.read_slave(received[total..])
    end
  end

  x.report("pty master->slave 1KiB vectored") do
    pty.write_master_v([payload[0, 512], payload[512, 512]])
    total = 0
    while total < payload.size
      total += pty.read_slave(received[total..])
    end
  end
end

pty.close
