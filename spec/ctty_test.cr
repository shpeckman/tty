# spec/ctty_test.cr
require "../src/tty"

def read_until_idle(pty : TTY::Pty, timeout : Time::Span = 2.seconds) : String
  io       = IO::Memory.new
  buffer   = Bytes.new(4096)
  deadline = Time.instant + timeout
  loop do
    remaining = deadline - Time.instant
    break if remaining <= Time::Span.zero
    got = nil
    ch  = Channel(Int32?).new
    spawn do
      begin
        ch.send pty.master.read(buffer)
      rescue
        ch.send nil
      end
    end
    select
    when n = ch.receive
      break if n.nil? || n == 0
      io.write buffer[0, n]
    when timeout remaining
      break
    end
  end
  io.to_s
end

failures = 0

check = ->(name : String, ok : Bool) do
  if ok
    puts "  ok   - #{name}"
  else
    puts "  FAIL - #{name}"
    failures += 1
  end
end

probe = File.join(__DIR__, "child_probe.sh")

pty    = TTY::Pty.new("/bin/sh", [probe], cols: 80, rows: 24)
output = read_until_idle(pty)
code   = pty.reap

puts "child output:"
output.each_line { |l| puts "    | #{l}" }

sid = output =~ /SID=(\d+)/ ? $1 : nil
pid = output =~ /PID=(\d+)/ ? $1 : nil

check.call "child exited cleanly", code == 0
check.call "child is a session leader (SID == PID)", !!(sid && pid && sid == pid)
check.call "child has a controlling terminal", output.includes?("HAS_CTTY=yes")
check.call "controlling tty is a pts device", output.includes?("TTYNAME=/dev/pts/")

puts ""
if failures.zero?
  puts "ALL PASSED"
  exit 0
else
  puts "#{failures} FAILED"
  exit 1
end
