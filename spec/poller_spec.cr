# spec/poller_spec.cr
require "./spec_helper"

describe TTY::Poller do
  it "uses the poll backend explicitly" do
    read_fd, write_fd = TTY::FD.pipe
    poller = TTY::Poller.new(TTY::PollerBackendKind::Poll)
    poller.backend.should eq(TTY::PollerBackendKind::Poll)
    poller.watch(read_fd, TTY::IOEvent::Readable)
    poller.wait(0).should be_empty

    TTY::Syscall.write(write_fd, "x")
    events = poller.wait(1000)
    events.size.should eq(1)
    events[0].fd.should eq(read_fd)
    events[0].readable?.should be_true

    poller.unwatch(read_fd)
    poller.wait(0).should be_empty
    poller.close
    poller.closed?.should be_true
    TTY::Syscall.close(read_fd)
    TTY::Syscall.close(write_fd)
  end

  {% unless flag?(:darwin) %}
    it "uses epoll as the Linux default backend" do
      sizeof(TTY::EpollEvent).should eq(12)
      read_fd, write_fd = TTY::FD.pipe
      poller = TTY::Poller.new
      poller.backend.should eq(TTY::PollerBackendKind::Epoll)
      poller.watch(read_fd, TTY::IOEvent::Readable)
      poller.wait(0).should be_empty

      TTY::Syscall.write(write_fd, "x")
      events = poller.wait(1000)
      events.size.should eq(1)
      events[0].fd.should eq(read_fd)
      events[0].readable?.should be_true

      poller.close
      TTY::Syscall.close(read_fd)
      TTY::Syscall.close(write_fd)
    end
  {% end %}

  {% if flag?(:darwin) %}
    it "uses kqueue as the Darwin default backend" do
      read_fd, write_fd = TTY::FD.pipe
      poller = TTY::Poller.new
      poller.backend.should eq(TTY::PollerBackendKind::Kqueue)
      poller.watch(read_fd, TTY::IOEvent::Readable)
      poller.wait(0).should be_empty

      TTY::Syscall.write(write_fd, "x")
      events = poller.wait(1000)
      events.size.should eq(1)
      events[0].fd.should eq(read_fd)
      events[0].readable?.should be_true

      poller.close
      TTY::Syscall.close(read_fd)
      TTY::Syscall.close(write_fd)
    end
  {% end %}
end
