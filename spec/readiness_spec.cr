# spec/readiness_spec.cr
require "./spec_helper"

describe "TTY readiness" do
  it "waits for readable data" do
    pty     = TTY::PTY.open
    termios = pty.termios
    termios.make_raw
    pty.termios = termios
    TTY.flush(pty.slave_fd)

    TTY.wait_readable(pty.slave_fd, 10.milliseconds).should be_false
    pty.write_master("x")
    TTY.wait_readable(pty.slave_fd, 1.second).should be_true
    buffer = Bytes.new(1)
    pty.read_slave(buffer).should eq 1
    buffer[0].should eq 'x'.ord.to_u8
    pty.close
  end

  it "reports writability and rejects invalid fds" do
    pty = TTY::PTY.open
    TTY.wait_writable(pty.master_fd, 0.milliseconds).should be_true
    pty.close

    error = expect_raises(TTY::Syscall::Error, /poll fd=-1/) { TTY.wait_readable(-1, 0.milliseconds) }
    error.errno.should eq Errno::EBADF.to_i
  end

  it "validates timeouts" do
    expect_raises(ArgumentError, /non-negative/) { TTY.wait_readable(0, (-1).milliseconds) }
  end
end
