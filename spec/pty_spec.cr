# spec/pty_spec.cr
require "./spec_helper"

describe TTY::PTY do
  it "allocates a master/slave pair" do
    pty = TTY::PTY.open
    pty.master_fd.should be >= 0
    pty.slave_fd.should be >= 0
    pty.slave_name.should match(/^\/dev\/pts\/\d+$/)
    pty.close
  end

  it "passes bytes from master to slave" do
    pty = TTY::PTY.open
    pty.write_master("hello\n")
    buffer = Bytes.new(6)
    pty.read_slave(buffer).should eq 6
    String.new(buffer).should eq "hello\n"
    pty.close
  end

  it "passes bytes from slave to master" do
    pty = TTY::PTY.open
    pty.write_slave("world")
    buffer = Bytes.new(5)
    pty.read_master(buffer).should eq 5
    String.new(buffer).should eq "world"
    pty.close
  end

  it "echoes input in cooked mode and not in raw mode" do
    pty = TTY::PTY.open
    pty.write_master("abc")
    buffer = Bytes.new(3)
    pty.read_master(buffer)
    String.new(buffer).should eq "abc"

    termios = pty.termios
    termios.make_raw
    pty.termios = termios
    TTY.flush(pty.slave_fd)
    pty.write_master("xyz")
    pty.read_slave(buffer)
    String.new(buffer).should eq "xyz"
    master_io = pty.master_io
    IO::FileDescriptor.set_blocking(master_io.fd, false)
    echo = Channel(Int32).new
    spawn do
      buf = Bytes.new(8)
      echo.send(master_io.read(buf))
    end
    select
    when echo.receive
      fail "expected no echo in raw mode"
    when timeout(0.2.seconds)
    end
    pty.close
  end

  it "performs line editing in cooked mode" do
    pty = TTY::PTY.open
    pty.write_master("ab\u007Fc\n")
    buffer = Bytes.new(16)
    n      = 0
    until n >= 3 && buffer[n - 1] == '\n'.ord.to_u8
      n += pty.read_slave(buffer[n..])
    end
    String.new(buffer[0, n]).should eq "ac\n"
    pty.close
  end
end
