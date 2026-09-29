# spec/termios_spec.cr
require "./spec_helper"

describe TTY::Termios do
  it "reads termios from a pty slave" do
    pty     = TTY::PTY.open
    termios = TTY::Termios.get(pty.slave_fd)
    termios.local.should_not eq TTY::LocalFlag::None
    pty.close
  end

  it "round-trips flag changes through the kernel" do
    pty      = TTY::PTY.open
    termios  = TTY::Termios.get(pty.slave_fd)
    original = termios.local
    termios.local = original & ~TTY::LocalFlag::Echo
    termios.set(pty.slave_fd)
    TTY::Termios.get(pty.slave_fd).local.should eq(original & ~TTY::LocalFlag::Echo)
    pty.close
  end

  it "make_raw clears canonical, echo, signals and output processing" do
    termios = TTY::Termios.new
    termios.local = TTY::LocalFlag::Echo | TTY::LocalFlag::ICanon | TTY::LocalFlag::ISig | TTY::LocalFlag::IExten
    termios.output = TTY::OutputFlag::OPost
    termios.input = TTY::InputFlag::ICrNl | TTY::InputFlag::IXon
    termios.make_raw
    termios.local.should eq TTY::LocalFlag::None
    termios.output.should eq TTY::OutputFlag::None
    termios.input.should eq TTY::InputFlag::None
    termios[TTY::ControlChar::Min].should eq 1_u8
    termios[TTY::ControlChar::Time].should eq 0_u8
  end

  it "TTY.raw restores the original settings after the block" do
    pty    = TTY::PTY.open
    before = TTY::Termios.get(pty.slave_fd)
    TTY.raw(pty.slave_fd) do
      TTY::Termios.get(pty.slave_fd).local.should eq(before.local & ~(TTY::LocalFlag::Echo | TTY::LocalFlag::EchoNl | TTY::LocalFlag::ICanon | TTY::LocalFlag::ISig | TTY::LocalFlag::IExten))
    end
    TTY::Termios.get(pty.slave_fd).local.should eq before.local
    pty.close
  end

  it "TTY.raw restores settings even when the block raises" do
    pty    = TTY::PTY.open
    before = TTY::Termios.get(pty.slave_fd)
    expect_raises(Exception) { TTY.raw(pty.slave_fd) { raise Exception.new("boom") } }
    TTY::Termios.get(pty.slave_fd).local.should eq before.local
    pty.close
  end

  it "raises TTY::Syscall::Error on an invalid fd" do
    expect_raises(TTY::Syscall::Error, /EBADF/) { TTY::Termios.get(-1) }
  end
end
