# spec/mode_spec.cr
require "./spec_helper"

describe "TTY scoped terminal modes" do
  it "applies raw mode for the duration of the block" do
    pty      = TTY::PTY.open
    original = TTY::Termios.get(pty.slave_fd)
    TTY.raw(pty.slave_fd) do
      inside = TTY::Termios.get(pty.slave_fd)
      inside.local.includes?(TTY::LocalFlag::Echo).should be_false
      inside.local.includes?(TTY::LocalFlag::ICanon).should be_false
      inside.output.includes?(TTY::OutputFlag::OPost).should be_false
    end
    TTY::Termios.get(pty.slave_fd).local.should eq(original.local)
    pty.close
  end

  it "restores the original termios when a raw block raises" do
    pty      = TTY::PTY.open
    original = TTY::Termios.get(pty.slave_fd)
    expect_raises(Exception, "boom") do
      TTY.raw(pty.slave_fd) { raise "boom" }
    end
    restored = TTY::Termios.get(pty.slave_fd)
    restored.input.should eq(original.input)
    restored.output.should eq(original.output)
    restored.control.should eq(original.control)
    restored.local.should eq(original.local)
    pty.close
  end

  it "restores the original termios when a cbreak block raises" do
    pty      = TTY::PTY.open
    original = TTY::Termios.get(pty.slave_fd)
    expect_raises(Exception, "boom") do
      TTY.cbreak(pty.slave_fd) { raise "boom" }
    end
    TTY::Termios.get(pty.slave_fd).local.should eq(original.local)
    pty.close
  end
end
