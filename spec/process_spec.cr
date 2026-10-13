# spec/process_spec.cr
require "./spec_helper"

describe TTY::PTY::Process do
  it "waits and caches status" do
    process = TTY::PTY.spawn("sh", ["-c", "exit 7"], env: {"PATH" => "/usr/bin:/bin"})
    read_until_eio(process.pty)
    process.exited?.should be_false
    status = process.wait
    status.exited?.should be_true
    status.exit_status.should eq 7
    process.wait.exit_status.should eq 7
    process.exited?.should be_true
    process.status.not_nil!.exit_status.should eq 7
    process.close
  end

  it "supports wait timeouts" do
    process = TTY::PTY.spawn("sleep", ["0.3"], env: {"PATH" => "/usr/bin:/bin"})
    process.wait(10).should be_nil
    status = process.wait(2000)
    status.should_not be_nil
    status.not_nil!.success?.should be_true
    process.close
  end

  it "returns promptly from a timed wait on an exited child" do
    process = TTY::PTY.spawn("sh", ["-c", "exit 5"], env: {"PATH" => "/usr/bin:/bin"})
    started = Time.instant
    status  = process.wait(5000)
    (Time.instant - started).should be < 2.seconds
    status.should_not be_nil
    status.not_nil!.exit_status.should eq 5
    process.close
  end

  it "terminates a running child" do
    process = TTY::PTY.spawn("sleep", ["30"], env: {"PATH" => "/usr/bin:/bin"})
    process.terminate
    status = process.wait(2000)
    status.should_not be_nil
    status.not_nil!.signaled?.should be_true
    status.not_nil!.term_signal.should eq TTY::Syscall::SIGTERM
    process.close
  end

  it "kills a running child" do
    process = TTY::PTY.spawn("sleep", ["30"], env: {"PATH" => "/usr/bin:/bin"})
    process.kill
    status = process.wait(2000)
    status.should_not be_nil
    status.not_nil!.signaled?.should be_true
    status.not_nil!.term_signal.should eq TTY::Syscall::SIGKILL
    process.close
  end

  it "closes the pty idempotently" do
    process = TTY::PTY.spawn("true", env: {"PATH" => "/usr/bin:/bin"})
    process.wait.success?.should be_true
    process.pty.close
    process.pty.close
    process.pty.closed?.should be_true
  end

  it "recovers the status when the runtime reaps the child first" do
    process = TTY::PTY.spawn("sh", ["-c", "exit 5"], env: {"PATH" => "/usr/bin:/bin"})
    sleep 200.milliseconds
    status = process.wait
    status.exited?.should be_true
    status.exit_status.should eq 5
    process.close
  end
end

describe "TTY::PTY::Process#interact" do
  it "relays piped input to the child and child output back" do
    input_read, input_write = IO.pipe
    output = IO::Memory.new
    flags   = TTY::FD.status_flags(input_read)
    process = TTY::PTY.spawn("sh", ["-c", "read line; echo \"got $line\""])
    input_write.puts "ping"
    status = process.interact(input_read, output)
    status.success?.should be_true
    output.to_s.should contain("got ping")
    TTY::FD.status_flags(input_read).should eq(flags)
    process.close
    input_read.close
    input_write.close
  end

  it "puts a terminal input into raw mode, mirrors its size and restores it" do
    outer = TTY::PTY.open
    outer.winsize = TTY::Winsize.new(rows: 21_u16, cols: 73_u16)
    terminal = outer.slave_io
    before   = TTY.termios(terminal)
    output   = IO::Memory.new
    process  = TTY::PTY.spawn("sh", ["-c", "stty size; read line; echo \"got $line\""])
    outer.write_master("pong\r")
    status = process.interact(terminal, output)
    status.success?.should be_true
    output.to_s.should contain("21 73")
    output.to_s.should contain("got pong")
    TTY.termios(terminal).local.should eq(before.local)
    process.close
    outer.close
  end
end
