# spec/winsize_spec.cr
require "./spec_helper"

describe TTY::Winsize do
  it "sets size on the master and reads it back from the slave" do
    pty = TTY::PTY.open
    TTY::Winsize.new(rows: 43_u16, cols: 131_u16).set(pty.master_fd)
    winsize = TTY::Winsize.get(pty.slave_fd)
    winsize.rows.should eq 43_u16
    winsize.cols.should eq 131_u16
    pty.close
  end

  it "PTY.spawn applies a winsize before exec" do
    process = TTY::PTY.spawn("sh", ["-c", "stty size"], env: {"PATH" => "/usr/bin:/bin"}, winsize: TTY::Winsize.new(rows: 55_u16, cols: 99_u16))
    read_until_eio(process.pty).should contain "55 99"
    process.wait
    process.pty.close
  end

  it "returns the current size for terminals and nil for non-terminals" do
    pty = TTY::PTY.open
    TTY::Winsize.current(pty.slave_fd).should_not be_nil
    pty.close

    read_fd, write_fd = TTY::FD.pipe
    TTY::Winsize.current(read_fd).should be_nil
    TTY::Syscall.close(read_fd)
    TTY::Syscall.close(write_fd)
  end

  it "propagates the current size immediately" do
    source = TTY::PTY.open
    target = TTY::PTY.open
    TTY::Winsize.new(rows: 33_u16, cols: 77_u16).set(source.slave_fd)
    TTY::Winsize.propagate(source.slave_fd, target.master_fd)
    size = TTY::Winsize.get(target.slave_fd)
    size.rows.should eq 33_u16
    size.cols.should eq 77_u16
    source.close
    target.close
  end
end
