# spec/spawn_spec.cr
require "./spec_helper"

describe "PTY.spawn reliability" do
  it "raises an exec error with errno and attempted paths" do
    error = expect_raises(TTY::PTY::ExecError) do
      TTY::PTY.spawn("tty-command-that-does-not-exist", env: {"PATH" => "/definitely/missing"})
    end
    error.errno.should eq(2)
    error.errno_name.should eq("ENOENT")
    error.command.should eq("tty-command-that-does-not-exist")
    error.attempts.should contain("/definitely/missing/tty-command-that-does-not-exist")
  end

  it "applies a working directory before exec" do
    process = TTY::PTY.spawn("pwd", env: {"PATH" => "/usr/bin:/bin"}, working_dir: "/tmp")
    output  = read_until_eio(process.pty)
    status  = process.wait
    status.success?.should be_true
    output.should contain("/tmp")
    process.close
  end

  it "accepts spawn options directly" do
    options = TTY::SpawnOptions.new(env: {"PATH" => "/usr/bin:/bin"}, working_dir: "/")
    process = TTY::PTY.spawn("pwd", [] of String, options)
    output  = read_until_eio(process.pty)
    process.wait.success?.should be_true
    output.should contain("/")
    process.close
  end

  it "provides a TERM fallback in the default child environment" do
    expected = ENV["TERM"]? || "xterm-256color"
    process  = TTY::PTY.spawn("sh", ["-c", "printf 'term=%s' \"$TERM\""])
    read_until_eio(process.pty).should contain "term=#{expected}"
    process.wait.success?.should be_true
    process.close
  end
end

describe "PTY.spawn environment and shell options" do
  it "merges env entries into the inherited environment" do
    ENV["TTY_SPEC_INHERITED"] = "kept"
    begin
      output, status = TTY::PTY.run("sh", ["-c", "printf '%s|%s' \"$TTY_SPEC_INHERITED\" \"$TTY_SPEC_ADDED\""], env: {"TTY_SPEC_ADDED" => "added"})
      status.success?.should be_true
      output.should eq("kept|added")
    ensure
      ENV.delete("TTY_SPEC_INHERITED")
    end
  end

  it "unsets variables mapped to nil" do
    ENV["TTY_SPEC_REMOVED"] = "present"
    begin
      output, _ = TTY::PTY.run("sh", ["-c", "printf '[%s]' \"${TTY_SPEC_REMOVED-unset}\""], env: {"TTY_SPEC_REMOVED" => nil})
      output.should eq("[unset]")
    ensure
      ENV.delete("TTY_SPEC_REMOVED")
    end
  end

  it "starts from an empty environment with clear_env" do
    output, _ = TTY::PTY.run("/usr/bin/env", clear_env: true, env: {"ONLY" => "this"})
    output.should eq("ONLY=this\n")
  end

  it "runs a shell command line with shell: true" do
    output, status = TTY::PTY.run("printf '%s-%s' a b | tr a-z A-Z", shell: true)
    status.success?.should be_true
    output.should eq("A-B")
  end

  it "passes args to a shell command as positional parameters" do
    output, _ = TTY::PTY.run("printf '%s,'", ["x", "y z"], shell: true)
    output.should eq("x,y z,")
  end

  it "exposes the resolved argv and environment" do
    options = TTY::SpawnOptions.new(env: {"A" => "1"}, clear_env: true, shell: true)
    options.environment.should eq({"A" => "1"})
    options.argv("echo", ["hi"]).should eq(["/bin/sh", "-c", %(echo "$@"), "sh", "hi"])
    TTY::SpawnOptions.new.argv("echo", ["hi"]).should eq(["echo", "hi"])
  end
end

describe "PTY.spawn block form" do
  it "returns the block value and reaps the child" do
    captured = nil.as(TTY::PTY::Process?)
    result = TTY::PTY.spawn("sh", ["-c", "echo ready; exit 3"]) do |process|
      captured = process
      process.gets.should eq("ready")
      process.wait.exit_code
    end
    result.should eq(3)
    captured.not_nil!.closed?.should be_true
    captured.not_nil!.exited?.should be_true
  end

  it "hangs up a child that is still running when the block ends" do
    captured = nil.as(TTY::PTY::Process?)
    TTY::PTY.spawn("cat") { |process| captured = process }
    status = captured.not_nil!.status.not_nil!
    status.signal_exit?.should be_true
    status.exit_signal.should eq(Signal::HUP)
  end

  it "cleans up when the block raises" do
    captured = nil.as(TTY::PTY::Process?)
    expect_raises(Exception, "boom") do
      TTY::PTY.spawn("cat") do |process|
        captured = process
        raise "boom"
      end
    end
    captured.not_nil!.exited?.should be_true
    captured.not_nil!.closed?.should be_true
  end

  it "accepts SpawnOptions in block form" do
    options = TTY::SpawnOptions.new(working_dir: "/tmp")
    output = TTY::PTY.spawn("pwd", [] of String, options, &.gets_to_end)
    output.should contain("/tmp")
  end
end

describe "PTY.run" do
  it "captures output without carriage returns and the status" do
    output, status = TTY::PTY.run("sh", ["-c", "printf 'one\\ntwo\\n'; exit 4"])
    output.should eq("one\ntwo\n")
    status.exit_code.should eq(4)
  end

  it "gives the child a terminal" do
    output, _ = TTY::PTY.run("sh", ["-c", "test -t 1 && echo tty"])
    output.should eq("tty\n")
  end

  it "raises exec errors" do
    expect_raises(TTY::PTY::ExecError) { TTY::PTY.run("tty-command-that-does-not-exist") }
  end
end
