# spec/conversions_spec.cr
require "./spec_helper"

describe "TTY argument conversions" do
  it "normalizes timeouts" do
    TTY.timeout_ms(nil).should eq(-1)
    TTY.timeout_ms(-1).should eq(-1)
    TTY.timeout_ms(250).should eq(250)
    TTY.timeout_ms(1.5.seconds).should eq(1500)
    TTY.timeout_ms(1.microsecond).should eq(1)
    TTY.timeout_ms(100.days).should eq(Int32::MAX)
    expect_raises(ArgumentError, /-1 or greater/) { TTY.timeout_ms(-2) }
    expect_raises(ArgumentError, /-1 or greater/) { TTY.timeout_ms(-1.second) }
  end

  it "accepts IO::FileDescriptor wherever an fd is expected" do
    pty   = TTY::PTY.open
    slave = pty.slave_io
    TTY.termios(slave).local.should eq(TTY.termios(pty.slave_fd).local)
    TTY::Winsize.new(rows: 12_u16, cols: 34_u16).set(pty.master_io)
    TTY.winsize(slave).cols.should eq(34_u16)
    TTY.wait_writable(slave, 0).should be_true
    TTY.raw(slave) { TTY.termios(slave).canonical?.should be_false }
    TTY::FD.character_device?(slave).should be_true
    pty.close
  end

  it "accepts Time::Span timeouts on readiness, poller and process waits" do
    pty = TTY::PTY.open
    pty.wait_readable(20.milliseconds).should be_false
    poller = TTY::Poller.new
    poller.watch(pty.master_io, TTY::IOEvent::Readable)
    poller.wait(10.milliseconds).should be_empty
    pty.write_slave("x")
    poller.wait(1.second).size.should eq(1)
    poller.unwatch(pty.master_fd)
    poller.close
    pty.close

    process = TTY::PTY.spawn("sleep", ["5"])
    process.wait(20.milliseconds).should be_nil
    process.signal(Signal::TERM)
    status = process.wait(2.seconds).not_nil!
    status.exit_signal.should eq(Signal::TERM)
    process.close
  end

  it "rejects negative process wait timeouts" do
    process = TTY::PTY.spawn("true")
    expect_raises(ArgumentError, /non-negative/) { process.wait(-1) }
    process.wait
    process.close
  end

  it "mirrors Process::Status names on child statuses and events" do
    exited = TTY::ChildStatus.new(3 << 8)
    exited.normal_exit?.should be_true
    exited.exit_code.should eq(3)
    exited.signal_exit?.should be_false

    killed = TTY::ChildStatus.new(Signal::KILL.value)
    killed.signal_exit?.should be_true
    killed.exit_signal.should eq(Signal::KILL)

    event = TTY::ChildEvent.from_wait_status(1, Signal::INT.value)
    event.signal_exit?.should be_true
    event.exit_signal.should eq(Signal::INT)
  end
end

{% unless flag?(:darwin) %}
  describe "TTY signal values" do
    it "accepts Signal members for process-group and wait_event APIs" do
      process = TTY::PTY.spawn("sleep", ["5"])
      process.wait_event(20.milliseconds).should be_nil
      TTY::Session.signal_process_group(process.pid, Signal::KILL)
      process.wait_event(2.seconds).not_nil!.exit_signal.should eq(Signal::KILL)
      process.close
    end
  end
{% end %}
