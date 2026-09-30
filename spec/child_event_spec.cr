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

    it "composes with wait when the event is observed first" do
      process = TTY::PTY.spawn("sh", ["-c", "exit 9"], env: {"PATH" => "/usr/bin:/bin"})
      event = process.wait_event
      event.exited?.should be_true
      process.wait.exit_status.should eq(9)
      process.status.not_nil!.exit_status.should eq(9)
      process.close
    end

    it "composes with wait when the status is observed first" do
      process = TTY::PTY.spawn("sh", ["-c", "exit 4"], env: {"PATH" => "/usr/bin:/bin"})
      process.wait.exit_status.should eq(4)
      event = process.wait_event
      event.exited?.should be_true
      event.exit_status.should eq(4)
      event.terminal?.should be_true
      process.close
    end

    it "recovers the event when the runtime reaps the child first" do
      process = TTY::PTY.spawn("sh", ["-c", "exit 7"], env: {"PATH" => "/usr/bin:/bin"})
      sleep 200.milliseconds
      event = process.wait_event
      event.exited?.should be_true
      event.exit_status.should eq(7)
      event.terminal?.should be_true
      process.wait.exit_status.should eq(7)
      process.close
    end

    it "reconstructs events from wait statuses" do
      exited = TTY::ChildEvent.from_wait_status(42, 3 << 8)
      exited.exited?.should be_true
      exited.exit_status.should eq(3)

      killed = TTY::ChildEvent.from_wait_status(42, 9)
      killed.signaled?.should be_true
      killed.term_signal.should eq(9)

      dumped = TTY::ChildEvent.from_wait_status(42, 9 | 0x80)
      dumped.core_dumped?.should be_true
      dumped.term_signal.should eq(9)

      stopped = TTY::ChildEvent.from_wait_status(42, 0x7f | (19 << 8))
      stopped.stopped?.should be_true
      stopped.stop_signal.should eq(19)
    end
  end
{% end %}
