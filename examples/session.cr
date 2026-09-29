# examples/session.cr
require "../src/tty"

process = TTY::PTY.spawn("sh", ["-c", "sleep 30"], env: {"PATH" => "/usr/bin:/bin"})
begin
  puts TTY::Session.foreground_pgrp(process.pty.master_fd)
rescue ex : TTY::Syscall::Error
  puts ex.message
end
process.terminate
process.wait
process.close
