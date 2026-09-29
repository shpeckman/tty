# spec/pidfd_spec.cr
require "./spec_helper"

{% unless flag?(:darwin) %}
  describe "PTY process pidfds" do
    it "opens a close-on-exec pidfd and polls process exit" do
      process = TTY::PTY.spawn("sleep", ["30"], env: {"PATH" => "/usr/bin:/bin"})
      pidfd = process.pidfd
      pidfd.should be >= 0
      TTY::FD.cloexec?(pidfd).should be_true
      process.poll_exit(10).should be_false

      process.terminate
      process.poll_exit(1000).should be_true
      status = process.wait
      status.signaled?.should be_true
      status.term_signal.should eq(TTY::Syscall::SIGTERM)
      process.close
    end
  end
{% end %}
