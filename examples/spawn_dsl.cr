# examples/spawn_dsl.cr
require "../src/tty"

process = TTY.spawn("sh", ["-c", "printf '%s@%s' \"$TTY_EXAMPLE\" \"$PWD\"; stty size"]) do
  env tty_example: "dsl"
  working_dir "/tmp"
  winsize rows: 40, cols: 100
end

buffer = Bytes.new(256)
begin
  while process.pty.wait_readable(1000)
    count = process.pty.read_master(buffer)
    break if count <= 0
    print String.new(buffer[0, count])
  end
rescue TTY::Syscall::Error
end
puts
puts process.wait.exit_status
process.close
