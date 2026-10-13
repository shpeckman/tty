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

describe "PTY::IO conveniences" do
  it "writes unbuffered by default" do
    process = TTY::PTY.spawn("cat")
    io      = process.io
    io.sync?.should be_true
    io.print "no-flush\n"
    io.expect("no-flush", timeout: 2.seconds)
    process.terminate
    process.wait
    process.close
  end

  it "returns the same evented IO on repeated access" do
    pty = TTY::PTY.open
    pty.io.should be(pty.io)
    pty.close
  end

  it "expects patterns and keeps unconsumed output for later reads" do
    process = TTY::PTY.spawn("sh", ["-c", "printf 'login: '; read name; echo \"hello $name\"; echo after"])
    match = process.expect(/login: /, timeout: 2.seconds)
    match[0].should eq("login: ")
    process.send_line("crystal")
    process.expect("hello crystal", timeout: 2.seconds).pre_match.should contain("crystal")
    process.gets.should eq("")
    process.gets.should eq("after")
    process.wait.success?.should be_true
    process.close
  end

  it "returns capture groups" do
    process = TTY::PTY.spawn("sh", ["-c", "echo 'version 1.2.3'"])
    match = process.expect(/version (\d+)\.(\d+)/, timeout: 2000)
    match[1].should eq("1")
    match[2].should eq("2")
    process.gets.should eq(".3")
    process.wait
    process.close
  end

  it "raises a timeout and preserves the received bytes" do
    process = TTY::PTY.spawn("sh", ["-c", "printf partial; sleep 5"])
    expect_raises(IO::TimeoutError) { process.expect("never", timeout: 300.milliseconds) }
    process.expect("partial", timeout: 1.second)
    process.kill
    process.wait
    process.close
  end

  it "raises end of stream when the child exits first" do
    process = TTY::PTY.spawn("sh", ["-c", "echo bye"])
    expect_raises(IO::EOFError) { process.expect("never", timeout: 2.seconds) }
    process.gets.should eq("bye")
    process.wait
    process.close
  end

  it "matches across invalid UTF-8 bytes" do
    process = TTY::PTY.spawn("sh", ["-c", "printf '\\377\\376marker'"])
    process.expect("marker", timeout: 2.seconds)[0].should eq("marker")
    process.wait
    process.close
  end
end

describe TTY::PTY::Process do
  it "acts as an IO over the child" do
    process = TTY::PTY.spawn("cat")
    process.puts "line"
    process.gets.should eq("line")
    process.gets.should eq("line")
    process.flush
    process.terminate
    process.wait
    process.close
    process.closed?.should be_true
    expect_raises(IO::Error, "Closed stream") { process.gets }
  end
end
