# spec/jobcontrol_test.cr
require "../src/tty"

def drain(pty : TTY::Pty, timeout : Time::Span = 2.seconds) : String
  io       = IO::Memory.new
  buffer   = Bytes.new(4096)
  deadline = Time.instant + timeout
  loop do
    remaining = deadline - Time.instant
    break if remaining <= Time::Span.zero
    ch = Channel(Int32?).new
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

pty = TTY::Pty.new("/bin/sh", ["-i"], cols: 80, rows: 24)
pty.write "echo READY=$?\n"
pty.write "kill -0 $$ && echo ALIVE\n"
pty.write "exit\n"
output = drain(pty)
pty.reap

puts "child output:"
output.each_line { |l| puts "    | #{l}" }
puts ""

no_jobctl = output.downcase.includes?("can't access tty") ||
            output.downcase.includes?("job control turned off")

if no_jobctl
  puts "  FAIL - interactive shell reported no job control"
  failures += 1
else
  puts "  ok   - interactive shell did not disable job control"
end

if output.includes?("ALIVE")
  puts "  ok   - interactive shell ran commands over the pty"
else
  puts "  FAIL - interactive shell did not run commands"
  failures += 1
end

puts ""
if failures.zero?
  puts "ALL PASSED"
  exit 0
else
  puts "#{failures} FAILED"
  exit 1
end
