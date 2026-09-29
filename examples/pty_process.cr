# examples/pty_process.cr
require "../src/tty"

process = TTY::PTY.spawn("sh", ["-c", "printf 'ready'; exit 3"], env: {"PATH" => "/usr/bin:/bin"})
output = String.build do |io|
  buffer = Bytes.new(128)
  loop do
    break unless process.pty.wait_readable(1000)
    begin
      count = process.pty.read_master(buffer)
      break if count <= 0
      io.write(buffer[0, count])
    rescue ex : TTY::Syscall::Error
      break if ex.errno == TTY::Syscall::EIO
      raise ex
    end
  end
end
status = process.wait
puts output
puts status.exit_status
process.close
