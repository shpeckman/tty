# src/tty/session.cr
require "./conversions"
require "./platform"
require "./syscall"

module TTY::Session
  def self.start : Int32
    Syscall.setsid
  end

  @[Deprecated("Use TTY::Session.start instead")]
  def self.leader : Int32
    start
  end

  def self.make_controlling(fd : Descriptor) : Nil
    Syscall.ioctl(TTY.fd_of(fd), TIOCSCTTY, 0)
  end

  def self.detach(fd : Descriptor) : Nil
    Syscall.ioctl(TTY.fd_of(fd), TIOCNOTTY, 0)
  end

  def self.id(fd : Descriptor) : Int32
    session_id = 0_i32
    Syscall.ioctl(TTY.fd_of(fd), TIOCGSID, pointerof(session_id))
    session_id
  end

  def self.foreground_pgrp(fd : Descriptor) : Int32
    pgrp = 0_i32
    Syscall.ioctl(TTY.fd_of(fd), TIOCGPGRP, pointerof(pgrp))
    pgrp
  end

  def self.set_foreground_pgrp(fd : Descriptor, pgrp : Int32) : Nil
    value = pgrp
    Syscall.ioctl(TTY.fd_of(fd), TIOCSPGRP, pointerof(value))
  end

  def self.process_group(pid : Int32 = 0) : Int32
    Syscall.getpgid(pid)
  end

  def self.set_process_group(pid : Int32, pgrp : Int32) : Nil
    Syscall.setpgid(pid, pgrp)
  end

  def self.signal_process_group(pgrp : Int32, signal : SignalValue) : Nil
    Syscall.killpg(pgrp, TTY.signal_number(signal))
  end

  def self.line_discipline(fd : Descriptor) : Int32
    discipline = 0_i32
    Syscall.ioctl(TTY.fd_of(fd), TIOCGETD, pointerof(discipline))
    discipline
  end

  def self.set_line_discipline(fd : Descriptor, discipline : Int32) : Nil
    value = discipline
    Syscall.ioctl(TTY.fd_of(fd), TIOCSETD, pointerof(value))
  end

  def self.exclusive(fd : Descriptor, enable : Bool = true) : Nil
    if enable
      Syscall.ioctl(TTY.fd_of(fd), TIOCEXCL, 0)
    else
      Syscall.ioctl(TTY.fd_of(fd), TIOCNXCL, 0)
    end
  end

  def self.exclusive?(fd : Descriptor) : Bool
    {% if flag?(:darwin) %}
      {% raise "TTY::Session.exclusive? is Linux-only" %}
    {% else %}
      value = 0_i32
      Syscall.ioctl(TTY.fd_of(fd), TIOCGEXCL, pointerof(value))
      value != 0
    {% end %}
  end
end
