# spec/control_spec.cr
require "./spec_helper"

describe "TTY control operations" do
  it "reports pending input bytes" do
    pty = TTY::PTY.open
    termios = pty.termios
    termios.make_raw
    pty.termios = termios
    TTY.flush(pty.slave_fd)
    pty.write_master("abc")
    sleep 0.1.seconds
    TTY.pending_input(pty.slave_fd).should eq 3
    pty.close
  end

  it "reports pending output bytes" do
    pty = TTY::PTY.open
    TTY.pending_output(pty.slave_fd).should eq 0
    pty.close
  end

  it "locks a pty exclusively and unlocks it" do
    pty = TTY::PTY.open
    TTY::Session.exclusive(pty.slave_fd)
    expect_raises(TTY::Syscall::Error, /EBUSY/) do
      TTY::Syscall.openat(pty.slave_name, TTY::Syscall::O_RDWR | TTY::Syscall::O_NOCTTY)
    end
    TTY::Session.exclusive(pty.slave_fd, enable: false)
    fd = TTY::Syscall.openat(pty.slave_name, TTY::Syscall::O_RDWR | TTY::Syscall::O_NOCTTY)
    TTY::Syscall.close(fd)
    pty.close
  end

  it "injects bytes via TIOCSTI when the kernel allows it" do
    unless File.exists?("/proc/sys/dev/tty/legacy_tiocsti") && File.read("/proc/sys/dev/tty/legacy_tiocsti").strip == "1"
      next
    end
    pty = TTY::PTY.open
    termios = pty.termios
    termios.make_raw
    pty.termios = termios
    TTY.flush(pty.slave_fd)
    TTY.inject(pty.slave_fd, 'z'.ord.to_u8)
    buffer = Bytes.new(1)
    pty.read_slave(buffer)
    buffer[0].should eq 'z'.ord.to_u8
    pty.close
  end

  it "toggles the break condition" do
    pty = TTY::PTY.open
    TTY.send_break(pty.slave_fd)
    TTY.clear_break(pty.slave_fd)
    pty.close
  end

  it "rejects modem status on a pty, which has no UART" do
    pty = TTY::PTY.open
    expect_raises(TTY::Syscall::Error, /ENOTTY/) { TTY.modem_status(pty.master_fd) }
    pty.close
  end
end
