# src/tty.cr
require "./tty/syscall"
require "./tty/termios"
require "./tty/winsize"
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

  def self.raw(fd : Int32, & : -> U) : U forall U
    original = Termios.get(fd)
    termios = original
    termios.make_raw
    termios.set(fd)
    begin
      yield
    ensure
      original.set(fd)
    end
  end

  def self.raw(io : IO::FileDescriptor, & : -> U) : U forall U
    raw(io.fd) { yield }
  end

  def self.cbreak(fd : Int32, & : -> U) : U forall U
    original = Termios.get(fd)
    termios = original
    termios.make_cbreak
    termios.set(fd)
    begin
      yield
    ensure
      original.set(fd)
    end
  end

  def self.cbreak(io : IO::FileDescriptor, & : -> U) : U forall U
    cbreak(io.fd) { yield }
  end
end
