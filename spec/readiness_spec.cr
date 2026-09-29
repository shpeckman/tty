# spec/readiness_spec.cr
require "./spec_helper"

describe "TTY readiness" do
  it "waits for readable data" do
    pty = TTY::PTY.open
    termios = pty.termios
    termios.make_raw
    pty.termios = termios
    TTY.flush(pty.slave_fd)

    TTY.wait_readable(pty.slave_fd, 10).should be_false
    pty.write_master("x")
    TTY.wait_readable(pty.slave_fd, 1000).should be_true
    buffer = Bytes.new(1)
    pty.read_slave(buffer).should eq 1
    buffer[0].should eq 'x'.ord.to_u8
    pty.close
  end

  it "reports writability and rejects invalid fds" do
    pty = TTY::PTY.open
    TTY.wait_writable(pty.master_fd, 0).should be_true
    pty.close

    error = expect_raises(TTY::Syscall::Error, /poll fd=-1/) { TTY.wait_readable(-1, 0) }
    error.errno.should eq TTY::Syscall::EBADF
  end

  it "validates timeouts" do
    expect_raises(ArgumentError, /-1 or greater/) { TTY.wait_readable(0, -2) }
  end
end
