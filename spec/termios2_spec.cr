# spec/termios2_spec.cr
require "./spec_helper"

{% unless flag?(:darwin) %}
  describe TTY::Termios2 do
    it "round-trips attributes through TCGETS2/TCSETS2" do
      pty = TTY::PTY.open
      termios = TTY::Termios2.get(pty.slave_fd)
      modified = termios.input & ~TTY::InputFlag::ICrNl
      termios.input = modified
      termios.set(pty.slave_fd)
      TTY::Termios2.get(pty.slave_fd).input.should eq(modified)
      pty.close
    end

    it "copies attributes from a Termios" do
      pty = TTY::PTY.open
      base = TTY::Termios.get(pty.slave_fd)
      copy = TTY::Termios2.from(base)
      copy.input.should eq(base.input)
      copy.output.should eq(base.output)
      copy.local.should eq(base.local)
      copy.line.should eq(base.line)
      TTY::ControlChar.each { |cc| copy[cc].should eq(base[cc]) }
      pty.close
    end

    it "tracks a custom baud rate through BOTHER" do
      pty = TTY::PTY.open
      termios = TTY::Termios2.get(pty.slave_fd)
      termios.custom_baud?.should be_false
      termios.custom_baud = 250_000_u32
      termios.custom_baud?.should be_true
      termios.input_speed.should eq(250_000_u32)
      termios.output_speed.should eq(250_000_u32)
      pty.close
    end
  end
{% end %}
