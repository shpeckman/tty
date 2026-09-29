# examples/spawn_error.cr
require "../src/tty"

begin
  TTY::PTY.spawn("command-that-does-not-exist", env: {"PATH" => "/definitely/missing"})
rescue ex : TTY::PTY::ExecError
  puts ex.errno_name
  puts ex.attempts.first
end
