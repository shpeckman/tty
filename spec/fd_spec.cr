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

  {% unless flag?(:darwin) %}
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

    it "closes fds through the procfs fallback walker" do
      read_fd, write_fd = TTY::FD.pipe
      pid = TTY::Syscall.fork
      if pid == 0
        result = TTY::Syscall.close_fds_via_procfs(read_fd, Int32::MAX, -1)
        TTY::Syscall.exit_group(3) if result < 0
        check = TTY::Syscall.raw(TTY::Syscall::NR_FCNTL, read_fd.to_i64, TTY::Syscall::F_GETFD.to_i64, 0_i64)
        TTY::Syscall.exit_group(check < 0 ? 0 : 5)
      end
      _, status = TTY::Syscall.wait4(pid)
      TTY::ChildStatus.new(status).exit_status.should eq(0)
      TTY::Syscall.close(read_fd)
      TTY::Syscall.close(write_fd)
    end
  {% end %}
end
