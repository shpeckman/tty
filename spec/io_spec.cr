# spec/io_spec.cr
require "./spec_helper"

describe TTY::PTY::IO do
  it "reads and writes through the evented IO wrapper" do
    process = TTY::PTY.spawn("cat", env: {"PATH" => "/usr/bin:/bin"})
    io      = process.pty.io
    io.puts "hello"
    io.flush
    io.gets.should eq("hello")
    process.terminate
    process.wait
    process.close
  end

  it "adopts the master into the event loop" do
    process = TTY::PTY.spawn("cat", env: {"PATH" => "/usr/bin:/bin"})
    io      = process.pty.io
    IO::FileDescriptor.get_blocking(io.fd).should be_false
    process.terminate
    process.wait
    process.close
  end

  it "does not block the scheduler while waiting for input" do
    process = TTY::PTY.spawn("sh", ["-c", "sleep 0.3; echo done"], env: {"PATH" => "/usr/bin:/bin"})
    io      = process.pty.io
    result  = Channel(String?).new
    spawn { result.send(io.gets) }
    ran = false
    spawn do
      sleep 0.15.seconds
      ran = true
    end
    result.receive.should eq("done")
    ran.should be_true
    process.wait
    process.close
  end

  it "reports end of stream once the child exits" do
    process = TTY::PTY.spawn("true", env: {"PATH" => "/usr/bin:/bin"})
    io      = process.pty.io
    process.wait
    io.gets.should be_nil
    process.close
  end

  it "raises on read errors when eof_on_error is disabled" do
    process = TTY::PTY.spawn("true", env: {"PATH" => "/usr/bin:/bin"})
    io      = TTY::PTY::IO.new(process.pty, eof_on_error: false)
    process.wait
    expect_raises(::IO::Error) { io.gets }
    process.close
  end

  it "closes the pty when the IO is closed" do
    process = TTY::PTY.spawn("cat", env: {"PATH" => "/usr/bin:/bin"})
    io      = process.pty.io
    io.close
    io.closed?.should be_true
    process.pty.closed?.should be_true
    expect_raises(::IO::Error) { io.gets }
    process.terminate
    process.wait
    process.close
  end
end
