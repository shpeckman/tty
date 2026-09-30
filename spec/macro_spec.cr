# spec/macro_spec.cr
require "./spec_helper"

describe TTY do
  describe "configure" do
    it "clears and sets local flags while preserving the rest" do
      pty      = TTY::PTY.open
      original = TTY::Termios.get(pty.slave_fd)
      TTY.configure(pty.slave_fd) do
        local -Echo, -ICanon
      end
      updated = TTY::Termios.get(pty.slave_fd)
      updated.local.should eq(original.local & ~(TTY::LocalFlag::Echo | TTY::LocalFlag::ICanon))
      updated.input.should eq original.input
      updated.output.should eq original.output
      pty.close
    end

    it "sets flags with unary plus" do
      pty = TTY::PTY.open
      TTY.configure(pty.slave_fd) do
        input -ICrNl
        input +IStrip
      end
      flags = TTY::Termios.get(pty.slave_fd).input
      flags.includes?(TTY::InputFlag::ICrNl).should be_false
      flags.includes?(TTY::InputFlag::IStrip).should be_true
      pty.close
    end

    it "applies raw mode" do
      pty    = TTY::PTY.open
      before = TTY::Termios.get(pty.slave_fd)
      TTY.configure(pty.slave_fd) do
        raw
      end
      termios = TTY::Termios.get(pty.slave_fd)
      termios.local.should eq(before.local & ~(TTY::LocalFlag::Echo | TTY::LocalFlag::EchoNl | TTY::LocalFlag::ICanon | TTY::LocalFlag::ISig | TTY::LocalFlag::IExten))
      termios.output.should eq(before.output & ~TTY::OutputFlag::OPost)
      termios[TTY::ControlChar::Min].should eq 1_u8
      termios[TTY::ControlChar::Time].should eq 0_u8
      pty.close
    end

    it "sets control characters" do
      pty = TTY::PTY.open
      TTY.configure(pty.slave_fd) do
        cbreak
        cc min: 4, time: 10
      end
      termios = TTY::Termios.get(pty.slave_fd)
      termios[TTY::ControlChar::Min].should eq 4_u8
      termios[TTY::ControlChar::Time].should eq 10_u8
      pty.close
    end

    it "sets the baud rate" do
      pty = TTY::PTY.open
      TTY.configure(pty.slave_fd) do
        baud B38400
      end
      TTY::Termios.get(pty.slave_fd).baud.should eq TTY::Baud::B38400
      pty.close
    end

    it "accepts an action override" do
      pty = TTY::PTY.open
      TTY.configure(pty.slave_fd) do
        local -Echo
        action :drain
      end
      TTY::Termios.get(pty.slave_fd).local.includes?(TTY::LocalFlag::Echo).should be_false
      pty.close
    end
  end

  describe "with_terminal" do
    it "applies raw mode and restores the original termios" do
      pty    = TTY::PTY.open
      before = TTY::Termios.get(pty.slave_fd)
      TTY.with_terminal(pty.slave_fd, raw: true) do
        TTY::Termios.get(pty.slave_fd).local.should eq(before.local & ~(TTY::LocalFlag::Echo | TTY::LocalFlag::EchoNl | TTY::LocalFlag::ICanon | TTY::LocalFlag::ISig | TTY::LocalFlag::IExten))
      end
      TTY::Termios.get(pty.slave_fd).local.should eq before.local
      pty.close
    end

    it "restores termios and fd flags when the block raises" do
      pty    = TTY::PTY.open
      before = TTY::Termios.get(pty.slave_fd)
      TTY::FD.nonblocking?(pty.slave_fd).should be_false
      expect_raises(Exception) do
        TTY.with_terminal(pty.slave_fd, raw: true, nonblocking: true) do
          TTY::FD.nonblocking?(pty.slave_fd).should be_true
          raise Exception.new("boom")
        end
      end
      TTY::Termios.get(pty.slave_fd).local.should eq before.local
      TTY::FD.nonblocking?(pty.slave_fd).should be_false
      pty.close
    end

    it "returns the block value" do
      pty = TTY::PTY.open
      result = TTY.with_terminal(pty.slave_fd, cbreak: true) do
        42
      end
      result.should eq 42
      pty.close
    end

    it "supports nonblocking-only scopes" do
      pty = TTY::PTY.open
      TTY.with_terminal(pty.slave_fd, nonblocking: true) do
        TTY::FD.nonblocking?(pty.slave_fd).should be_true
      end
      TTY::FD.nonblocking?(pty.slave_fd).should be_false
      pty.close
    end
  end

  describe "spawn" do
    it "spawns a process with declared env and working directory" do
      process = TTY.spawn("sh", ["-c", "printf '%s|' \"$TTY_MACRO_TEST\"; pwd"]) do
        env tty_macro_test: "macro-env"
        working_dir "/tmp"
      end
      output = read_until_eio(process.pty)
      status = process.wait
      output.should contain "macro-env|/tmp"
      status.exit_status.should eq 0
      process.close
    end

    it "merges declared env with the default environment" do
      process = TTY.spawn("sh", ["-c", "printf '%s' \"$TERM\""]) do
        env tty_macro_test: "x"
      end
      output = read_until_eio(process.pty)
      process.wait
      output.should_not be_empty
      process.close
    end

    it "spawns without options" do
      process = TTY.spawn("printf", ["spawn-ok"]) do
      end
      output = read_until_eio(process.pty)
      status = process.wait
      output.should contain "spawn-ok"
      status.exit_status.should eq 0
      process.close
    end
  end

  describe "Syscall def_syscall wrappers" do
    it "round-trips read and write through a pipe" do
      read_fd, write_fd = TTY::FD.pipe
      written = TTY::Syscall.write(write_fd, "macro")
      written.should eq 5
      buffer = Bytes.new(8)
      count  = TTY::Syscall.read(read_fd, buffer.to_unsafe, buffer.size)
      String.new(buffer[0, count]).should eq "macro"
      TTY::Syscall.close(read_fd)
      TTY::Syscall.close(write_fd)
    end

    it "returns the current pid from getpid" do
      TTY::Syscall.getpid.should eq ::Process.pid
    end

    it "raises a structured error with the operation and fd" do
      error = expect_raises(TTY::Syscall::Error) do
        TTY::Syscall.read(-1, Pointer(UInt8).null, 1)
      end
      error.errno.should eq TTY::Syscall::EBADF
      error.operation.should eq "read"
      error.fd.should eq -1
    end
  end
end
