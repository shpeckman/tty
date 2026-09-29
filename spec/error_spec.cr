# spec/error_spec.cr
require "./spec_helper"

describe TTY::Syscall::Error do
  it "carries operation and fd context" do
    buffer = Bytes.new(1)
    error = expect_raises(TTY::Syscall::Error, /read fd=-1 failed: EBADF/) { TTY::Syscall.read(-1, buffer.to_unsafe, buffer.size) }
    error.errno.should eq TTY::Syscall::EBADF
    error.operation.should eq "read"
    error.fd.should eq -1
    error.path.should be_nil
    error.request.should be_nil
  end

  it "carries ioctl request context" do
    error = expect_raises(TTY::Syscall::Error, /ioctl fd=-1 request=0x5401/) { TTY::Termios.get(-1) }
    error.errno.should eq TTY::Syscall::EBADF
    error.operation.should eq "ioctl"
    error.fd.should eq -1
    error.request.should eq TTY::TCGETS
  end
end
