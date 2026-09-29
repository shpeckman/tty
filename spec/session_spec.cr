# spec/session_spec.cr
require "./spec_helper"

describe TTY::Session do
  it "raises ENOTTY querying foreground pgrp on a session-less pty" do
    pty = TTY::PTY.open
    expect_raises(TTY::Syscall::Error, /ENOTTY/) { TTY::Session.foreground_pgrp(pty.slave_fd) }
    pty.close
  end

  it "PTY.spawn gives the child a controlling terminal" do
    process = TTY::PTY.spawn("tty")
    output  = read_until_eio(process.pty)
    output.should contain process.pty.slave_name
    process.wait.success?.should be_true
    process.pty.close
  end

  it "PTY.spawn passes args and env to the child" do
    process = TTY::PTY.spawn("sh", ["-c", "echo value=$FOO"], env: {"FOO" => "bar", "PATH" => "/usr/bin:/bin"})
    read_until_eio(process.pty).should contain "value=bar"
    process.wait.success?.should be_true
    process.pty.close
  end

  it "PTY.spawn reports child exit status" do
    process = TTY::PTY.spawn("sh", ["-c", "exit 42"], env: {"PATH" => "/usr/bin:/bin"})
    read_until_eio(process.pty)
    status = process.wait
    status.exited?.should be_true
    status.exit_status.should eq 42
    process.pty.close
  end

  it "PTY.spawn delivers SIGWINCH to the foreground job on resize" do
    process = TTY::PTY.spawn("sh", ["-c", "trap 'echo RESIZED' WINCH; sleep 2"], env: {"PATH" => "/usr/bin:/bin"})
    sleep 0.3.seconds
    TTY::Winsize.new(rows: 50_u16, cols: 120_u16).set(process.pty.master_fd)
    read_until_eio(process.pty).should contain "RESIZED"
    process.wait
    process.pty.close
  end
end
