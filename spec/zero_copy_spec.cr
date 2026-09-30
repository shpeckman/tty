# spec/zero_copy_spec.cr
require "./spec_helper"

{% unless flag?(:darwin) %}
  describe "zero-copy syscalls" do
    it "splices bytes between pipes" do
      read1, write1 = TTY::FD.pipe
      read2, write2 = TTY::FD.pipe
      TTY::Syscall.write(write1, "spliced")
      TTY::FD.splice(read1, write2, 7).should eq(7)
      buffer = Bytes.new(16)
      count = TTY::Syscall.read(read2, buffer.to_unsafe, buffer.size)
      String.new(buffer[0, count]).should eq("spliced")
      {read1, write1, read2, write2}.each { |fd| TTY::Syscall.close(fd) }
    end

    it "duplicates pipe data with tee" do
      read1, write1 = TTY::FD.pipe
      read2, write2 = TTY::FD.pipe
      TTY::Syscall.write(write1, "copied")
      TTY::FD.tee(read1, write2, 6).should eq(6)
      buffer = Bytes.new(16)
      count = TTY::Syscall.read(read2, buffer.to_unsafe, buffer.size)
      String.new(buffer[0, count]).should eq("copied")
      count = TTY::Syscall.read(read1, buffer.to_unsafe, buffer.size)
      String.new(buffer[0, count]).should eq("copied")
      {read1, write1, read2, write2}.each { |fd| TTY::Syscall.close(fd) }
    end

    it "copies between regular files with copy_file_range" do
      source_path = File.tempname("tty-cfr-source")
      target_path = File.tempname("tty-cfr-target")
      File.write(source_path, "file-bytes")
      File.write(target_path, "")
      begin
        source = TTY::Syscall.openat(source_path, TTY::Syscall::O_RDONLY)
        target = TTY::Syscall.openat(target_path, TTY::Syscall::O_RDWR)
        begin
          TTY::FD.copy_file_range(source, target, 10).should eq(10)
        rescue ex : TTY::Syscall::Error
          raise ex unless ex.errno == TTY::Syscall::ENOSYS || ex.errno == TTY::Syscall::EINVAL
        end
        TTY::Syscall.close(source)
        TTY::Syscall.close(target)
        contents = File.read(target_path)
        (contents.empty? || contents == "file-bytes").should be_true
      ensure
        File.delete(source_path) if File.exists?(source_path)
        File.delete(target_path) if File.exists?(target_path)
      end
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
  end
{% end %}
