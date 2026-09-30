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
