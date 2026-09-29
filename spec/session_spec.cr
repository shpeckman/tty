# spec/session_spec.cr
require "./spec_helper"

describe TTY::Session do
  it "raises ENOTTY querying foreground pgrp on a session-less pty" do
    pty = TTY::PTY.open
    expect_raises(TTY::Syscall::Error, /ENOTTY/) { TTY::Session.foreground_pgrp(pty.slave_fd) }
    pty.close
  end

  it "PTY.spawn gives the child a controlling terminal" do
    pid, pty = TTY::PTY.spawn("tty")
    output = read_until_eio(pty)
    output.should contain pty.slave_name
    TTY::PTY.wait(pid).success?.should be_true
    pty.close
  end

  it "PTY.spawn passes args and env to the child" do
    pid, pty = TTY::PTY.spawn("sh", ["-c", "echo value=$FOO"], env: {"FOO" => "bar", "PATH" => "/usr/bin:/bin"})
    read_until_eio(pty).should contain "value=bar"
    TTY::PTY.wait(pid).success?.should be_true
    pty.close
  end

  it "PTY.spawn reports child exit status" do
    pid, pty = TTY::PTY.spawn("sh", ["-c", "exit 42"], env: {"PATH" => "/usr/bin:/bin"})
    read_until_eio(pty)
    status = TTY::PTY.wait(pid)
    status.exited?.should be_true
    status.exit_status.should eq 42
    pty.close
  end

  it "PTY.spawn delivers SIGWINCH to the foreground job on resize" do
    pid, pty = TTY::PTY.spawn("sh", ["-c", "trap 'echo RESIZED' WINCH; sleep 2"], env: {"PATH" => "/usr/bin:/bin"})
    sleep 0.3.seconds
    TTY::Winsize.new(rows: 50_u16, cols: 120_u16).set(pty.master_fd)
    read_until_eio(pty).should contain "RESIZED"
    TTY::PTY.wait(pid)
    pty.close
  end
end
