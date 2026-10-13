# src/tty.cr
require "./tty/error"
require "./tty/conversions"
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
require "./tty/io"
require "./tty/macros"

module TTY
  def self.termios(fd : Descriptor) : Termios
    Termios.get(fd)
  end

  def self.winsize(fd : Descriptor) : Winsize
    Winsize.get(fd)
  end

  def self.nonblocking?(fd : Descriptor) : Bool
    FD.nonblocking?(fd)
  end

  def self.set_nonblocking(fd : Descriptor, enabled : Bool = true) : Nil
    FD.set_nonblocking(fd, enabled)
  end

  def self.cloexec?(fd : Descriptor) : Bool
    FD.cloexec?(fd)
  end

  def self.set_cloexec(fd : Descriptor, enabled : Bool = true) : Nil
    FD.set_cloexec(fd, enabled)
  end

  def self.raw(fd : Descriptor, action : SetAction = SetAction::Now, & : -> U) : U forall U
    original = Termios.get(fd)
    scoped_termios(fd, original, original.raw, action) { yield }
  end

  def self.cbreak(fd : Descriptor, action : SetAction = SetAction::Now, & : -> U) : U forall U
    original = Termios.get(fd)
    scoped_termios(fd, original, original.cbreak, action) { yield }
  end

  def self.modify_termios(fd : Descriptor, action : SetAction = SetAction::Now, & : Termios -> Termios) : Termios
    termios = yield Termios.get(fd)
    termios.set(fd, action)
    termios
  end

  private def self.scoped_termios(fd : Descriptor, original : Termios, configured : Termios, action : SetAction, & : -> U) : U forall U
    configured.set(fd, action)
    begin
      yield
    ensure
      original.set(fd)
    end
  end
end
