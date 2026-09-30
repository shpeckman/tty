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
    echo = Channel(Int32).new(1)
    spawn do
      buf = Bytes.new(8)
      begin
        echo.send(master_io.read(buf))
      rescue IO::Error
        echo.send(-1)
      end
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

  {% unless flag?(:darwin) %}
    it "opens an additional slave peer directly and reports lock state" do
      pty = TTY::PTY.open
      flags = (TTY::Syscall::O_RDWR | TTY::Syscall::O_NOCTTY | TTY::Syscall::O_CLOEXEC).to_i32
      peer = TTY::Syscall.ioctl_result(pty.master_fd, TTY::TIOCGPTPEER, flags)
      peer.should be >= 0
      TTY::FD.character_device?(peer).should be_true
      pty.locked?.should be_false
      TTY::Syscall.close(peer)
      pty.close
    end
  {% end %}

  it "transfers master data with vectored reads and writes" do
    pty = TTY::PTY.open
    pty.write_master_v(["he".to_slice, "llo\n".to_slice]).should eq(6)
    first  = Bytes.new(2)
    second = Bytes.new(8)
    pty.wait_readable(1000).should be_true
    read = pty.read_master_v([first, second])
    read.should eq(7)
    (String.new(first[0, 2]) + String.new(second[0, read - 2])).should eq("hello\r\n")
    pty.close
  end

  it "returns zero on master reads after slave teardown" do
    process = TTY::PTY.spawn("true", env: {"PATH" => "/usr/bin:/bin"})
    process.wait
    buffer = Bytes.new(16)
    process.pty.read_master(buffer).should eq(0)
    process.pty.read_master_v([buffer]).should eq(0)
    process.close
  end

  it "still raises EIO on master reads when eof_on_error is disabled" do
    process = TTY::PTY.spawn("true", env: {"PATH" => "/usr/bin:/bin"})
    process.pty.eof_on_error = false
    process.wait
    buffer = Bytes.new(16)
    expect_raises(TTY::Syscall::Error, /EIO/) { process.pty.read_master(buffer) }
    process.close
  end
end
