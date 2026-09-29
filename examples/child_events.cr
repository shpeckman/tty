# examples/child_events.cr
require "../src/tty"

process = TTY::PTY.spawn("sh", ["-c", "exit 3"], env: {"PATH" => "/usr/bin:/bin"})
event   = process.wait_event
puts event.kind
puts event.exit_status
process.close
