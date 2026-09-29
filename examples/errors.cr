# examples/errors.cr
require "../src/tty"

buffer = Bytes.new(1)
begin
  TTY::Syscall.read(-1, buffer.to_unsafe, buffer.size)
rescue ex : TTY::Syscall::Error
  puts ex.errno
  puts ex.errno_name
  puts ex.operation
  puts ex.fd
end
