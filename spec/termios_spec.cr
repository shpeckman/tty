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

  it "TTY.raw accepts a drain action" do
    pty = TTY::PTY.open
    TTY.raw(pty.slave_fd, action: TTY::SetAction::Drain) do
      TTY::Termios.get(pty.slave_fd).local.includes?(TTY::LocalFlag::ICanon).should be_false
    end
    pty.close
  end

  it "raises TTY::Syscall::Error on an invalid fd" do
    expect_raises(TTY::Syscall::Error, /EBADF/) { TTY::Termios.get(-1) }
  end

  it "round-trips a baud rate through the kernel" do
    pty     = TTY::PTY.open
    termios = TTY::Termios.get(pty.slave_fd)
    termios.baud = TTY::Baud::B19200
    termios.set(pty.slave_fd)
    TTY::Termios.get(pty.slave_fd).baud.should eq TTY::Baud::B19200
    pty.close
  end

  it "maps read_timeout onto VMIN and VTIME" do
    termios = TTY::Termios.new
    termios.read_timeout = 250.milliseconds
    termios[TTY::ControlChar::Min].should eq 0_u8
    termios[TTY::ControlChar::Time].should eq 2_u8
    termios.read_timeout.try(&.total_milliseconds).should eq 200.0
    termios.read_timeout = nil
    termios[TTY::ControlChar::Min].should eq 1_u8
    termios[TTY::ControlChar::Time].should eq 0_u8
    termios.read_timeout.should be_nil
  end

  it "treats a zero VTIME as no timeout regardless of VMIN" do
    termios = TTY::Termios.new
    termios[TTY::ControlChar::Min] = 5_u8
    termios[TTY::ControlChar::Time] = 0_u8
    termios.read_timeout.should be_nil
  end

  it "times out a raw-mode read after VTIME" do
    pty     = TTY::PTY.open
    termios = pty.termios
    termios.make_raw
    termios.read_timeout = 200.milliseconds
    pty.termios = termios
    TTY.flush(pty.slave_fd)
    started = Time.instant
    buffer  = Bytes.new(8)
    n       = pty.read_slave(buffer)
    elapsed = Time.instant - started
    n.should eq 0
    elapsed.should be >= 150.milliseconds
    pty.close
  end

  it "renders an stty-style summary" do
    pty     = TTY::PTY.open
    termios = TTY::Termios.get(pty.slave_fd)
    text    = termios.to_s
    text.should contain "intr = ^C"
    text.should contain "icanon"
    termios.local = termios.local & ~TTY::LocalFlag::Echo
    text = termios.to_s
    text.should contain "-echo"
    text.should_not contain " csize"
    pty.close
  end
end

{% unless flag?(:darwin) %}
  describe TTY::Termios2 do
    it "round-trips an arbitrary baud rate via BOTHER" do
      pty = TTY::PTY.open
      termios = TTY::Termios2.from(TTY::Termios.get(pty.slave_fd))
      termios.custom_baud = 12345_u32
      termios.set(pty.slave_fd)
      reread = TTY::Termios2.get(pty.slave_fd)
      reread.custom_baud?.should be_true
      reread.input_speed.should eq 12345_u32
      reread.output_speed.should eq 12345_u32
      TTY::Termios.get(pty.slave_fd).custom_baud?.should be_true
      pty.close
    end
  end
{% end %}
