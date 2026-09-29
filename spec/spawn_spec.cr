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
end
