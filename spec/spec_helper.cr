# spec/spec_helper.cr
require "spec"
require "../src/tty"

def read_until_eio(pty : TTY::PTY) : String
  buffer = Bytes.new(256)
  output = IO::Memory.new
  loop do
    begin
      n = pty.read_master(buffer)
    rescue TTY::Syscall::Error
      break
    end
    break if n <= 0
    output.write(buffer[0, n])
  end
  output.to_s
end
