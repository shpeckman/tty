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
    pid, pty = TTY::PTY.spawn("sh", ["-c", "stty size"], env: {"PATH" => "/usr/bin:/bin"}, winsize: TTY::Winsize.new(rows: 55_u16, cols: 99_u16))
    read_until_eio(pty).should contain "55 99"
    TTY::PTY.wait(pid)
    pty.close
  end
end
