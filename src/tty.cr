# src/tty.cr
require "./tty/error"
require "./tty/platform"
require "./tty/syscall"
require "./tty/fd"
require "./tty/readiness"
require "./tty/poller"
require "./tty/termios"
require "./tty/termios2"
require "./tty/winsize"
require "./tty/session"
require "./tty/control"
require "./tty/pty"

module TTY
  def self.termios(fd : Int32) : Termios
    Termios.get(fd)
  end

  def self.termios(io : IO::FileDescriptor) : Termios
    Termios.get(io.fd)
  end

  def self.winsize(fd : Int32) : Winsize
    Winsize.get(fd)
  end

  def self.winsize(io : IO::FileDescriptor) : Winsize
    Winsize.get(io.fd)
  end

  def self.nonblocking?(fd : Int32) : Bool
    FD.nonblocking?(fd)
  end

  def self.set_nonblocking(fd : Int32, enabled : Bool = true) : Nil
    FD.set_nonblocking(fd, enabled)
  end

  def self.cloexec?(fd : Int32) : Bool
    FD.cloexec?(fd)
  end

  def self.set_cloexec(fd : Int32, enabled : Bool = true) : Nil
    FD.set_cloexec(fd, enabled)
  end

  def self.raw(fd : Int32, action : SetAction = SetAction::Now, & : -> U) : U forall U
    original = Termios.get(fd)
    termios  = original
    termios.make_raw
    termios.set(fd, action)
    begin
      yield
    ensure
      original.set(fd)
    end
  end

  def self.raw(io : IO::FileDescriptor, action : SetAction = SetAction::Now, & : -> U) : U forall U
    raw(io.fd, action) { yield }
  end

  def self.cbreak(fd : Int32, action : SetAction = SetAction::Now, & : -> U) : U forall U
    original = Termios.get(fd)
    termios  = original
    termios.make_cbreak
    termios.set(fd, action)
    begin
      yield
    ensure
      original.set(fd)
    end
  end

  def self.cbreak(io : IO::FileDescriptor, action : SetAction = SetAction::Now, & : -> U) : U forall U
    cbreak(io.fd, action) { yield }
  end
end
