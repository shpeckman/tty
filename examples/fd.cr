# examples/fd.cr
require "../src/tty"

read_fd, write_fd = TTY::FD.pipe
TTY::FD.set_nonblocking(read_fd)
TTY::Syscall.write(write_fd, "hello")
buffer = Bytes.new(5)
TTY::Syscall.read(read_fd, buffer.to_unsafe, buffer.size)
puts String.new(buffer)
puts TTY::FD.cloexec?(read_fd)
TTY::Syscall.close(read_fd)
TTY::Syscall.close(write_fd)
