# examples/packet.cr
require "../src/tty"

pty = TTY::PTY.open
pty.packet_mode = true
pty.write_slave("packet")
buffer = Bytes.new(32)
packet = pty.read_packet(buffer)
puts packet.kind
puts String.new(buffer[0, packet.size])
pty.close
