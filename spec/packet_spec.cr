# spec/packet_spec.cr
require "./spec_helper"

describe "PTY packet mode" do
  it "round-trips slave data as a data packet" do
    pty = TTY::PTY.open
    pty.packet_mode = true
    pty.packet_mode?.should be_true

    pty.write_slave("abc")
    buffer = Bytes.new(16)
    packet = pty.read_packet(buffer)
    packet.data?.should be_true
    packet.size.should eq(3)
    String.new(buffer[0, packet.size]).should eq("abc")

    pty.packet_mode = false
    pty.packet_mode?.should be_false
    pty.close
  end

  it "reports queue flushes as control packets" do
    pty = TTY::PTY.open
    pty.packet_mode = true
    TTY.flush(pty.slave_fd, TTY::FlushQueue::Input)

    pty.wait_priority(1000).should be_true
    buffer = Bytes.new(16)
    packet = pty.read_packet(buffer)
    packet.control?.should be_true
    packet.events.includes?(TTY::PacketEvent::FlushRead).should be_true

    pty.close
  end
end
