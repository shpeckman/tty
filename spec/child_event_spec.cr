# spec/child_event_spec.cr
require "./spec_helper"

{% unless flag?(:darwin) %}
  describe "PTY child events" do
    it "reports a normal exit through waitid" do
      process = TTY::PTY.spawn("sh", ["-c", "exit 3"], env: {"PATH" => "/usr/bin:/bin"})
      event = process.wait_event
      event.exited?.should be_true
      event.exit_status.should eq(3)
      event.pid.should eq(process.pid)
      event.terminal?.should be_true
      process.status.not_nil!.exit_status.should eq(3)
      process.close
    end

    it "supports waitid timeouts and reports signaled termination" do
      process = TTY::PTY.spawn("sleep", ["30"], env: {"PATH" => "/usr/bin:/bin"})
      process.wait_event(10).should be_nil
      process.terminate
      event = process.wait_event(1000).not_nil!
      event.signaled?.should be_true
      event.term_signal.should eq(TTY::Syscall::SIGTERM)
      process.close
    end

    it "reports stopped and continued state changes" do
      process = TTY::PTY.spawn("sleep", ["30"], env: {"PATH" => "/usr/bin:/bin"})
      process.signal(TTY::Syscall::SIGSTOP)
      stopped = process.wait_event
      stopped.stopped?.should be_true
      stopped.stop_signal.should eq(TTY::Syscall::SIGSTOP)

      process.signal(TTY::Syscall::SIGCONT)
      continued = process.wait_event
      continued.continued?.should be_true

      process.kill
      killed = process.wait_event
      killed.signaled?.should be_true
      killed.term_signal.should eq(TTY::Syscall::SIGKILL)
      process.close
    end
  end
{% end %}
