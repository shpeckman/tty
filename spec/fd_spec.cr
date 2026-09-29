# spec/fd_spec.cr
require "./spec_helper"

describe TTY::FD do
  it "creates close-on-exec pipes and toggles descriptor flags" do
    read_fd, write_fd = TTY::FD.pipe
    TTY::FD.cloexec?(read_fd).should be_true
    TTY::FD.cloexec?(write_fd).should be_true

    TTY::FD.set_cloexec(read_fd, false)
    TTY::FD.cloexec?(read_fd).should be_false
    TTY::FD.set_cloexec(read_fd)
    TTY::FD.cloexec?(read_fd).should be_true

    TTY::FD.set_nonblocking(read_fd)
    TTY::FD.nonblocking?(read_fd).should be_true
    TTY::FD.set_nonblocking(read_fd, false)
    TTY::FD.nonblocking?(read_fd).should be_false

    TTY::Syscall.close(read_fd)
    TTY::Syscall.close(write_fd)
  end

  it "transfers data with readv and writev" do
    fds = uninitialized Int32[2]
    TTY::Syscall.socketpair(TTY::Syscall::AF_UNIX, TTY::Syscall::SOCK_STREAM, 0, fds.to_unsafe)
    left  = fds[0]
    right = fds[1]

    written = TTY::FD.writev(left, ["he".to_slice, "llo".to_slice])
    written.should eq(5)

    first  = Bytes.new(2)
    second = Bytes.new(3)
    read   = TTY::FD.readv(right, [first, second])
    read.should eq(5)
    String.new(first).should eq("he")
    String.new(second).should eq("llo")

    TTY::Syscall.close(left)
    TTY::Syscall.close(right)
  end

  it "duplicates with dup3 and closes an explicit fd range" do
    read_fd, write_fd = TTY::FD.pipe
    duplicate = TTY::Syscall.fcntl(read_fd, TTY::Syscall::F_DUPFD_CLOEXEC, 200_i64)
    duplicate.should be >= 200
    TTY::FD.cloexec?(duplicate).should be_true

    TTY::FD.close_range(duplicate, duplicate)
    byte = 0_u8
    expect_raises(TTY::Syscall::Error) do
      TTY::Syscall.read(duplicate, pointerof(byte), 1)
    end

    TTY::Syscall.close(read_fd)
    TTY::Syscall.close(write_fd)
  end

  it "reports stat metadata for a pty character device" do
    pty = TTY::PTY.open
    TTY::FD.character_device?(pty.master_fd).should be_true
    TTY::FD.stat(pty.master_fd).mode.should_not eq(0_u32)
    pty.close
  end
end
