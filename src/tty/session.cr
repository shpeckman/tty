# src/tty/session.cr
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

  def self.make_controlling(fd : Int32) : Nil
    Syscall.ioctl(fd, TIOCSCTTY, 0)
  end

  def self.detach(fd : Int32) : Nil
    Syscall.ioctl(fd, TIOCNOTTY, 0)
  end

  def self.id(fd : Int32) : Int32
    session_id = 0_i32
    Syscall.ioctl(fd, TIOCGSID, pointerof(session_id))
    session_id
  end

  def self.foreground_pgrp(fd : Int32) : Int32
    pgrp = 0_i32
    Syscall.ioctl(fd, TIOCGPGRP, pointerof(pgrp))
    pgrp
  end

  def self.set_foreground_pgrp(fd : Int32, pgrp : Int32) : Nil
    value = pgrp
    Syscall.ioctl(fd, TIOCSPGRP, pointerof(value))
  end

  def self.process_group(pid : Int32 = 0) : Int32
    Syscall.getpgid(pid)
  end

  def self.set_process_group(pid : Int32, pgrp : Int32) : Nil
    Syscall.setpgid(pid, pgrp)
  end

  def self.signal_process_group(pgrp : Int32, signal : Int32) : Nil
    Syscall.killpg(pgrp, signal)
  end

  def self.line_discipline(fd : Int32) : Int32
    discipline = 0_i32
    Syscall.ioctl(fd, TIOCGETD, pointerof(discipline))
    discipline
  end

  def self.set_line_discipline(fd : Int32, discipline : Int32) : Nil
    value = discipline
    Syscall.ioctl(fd, TIOCSETD, pointerof(value))
  end

  def self.exclusive(fd : Int32, enable : Bool = true) : Nil
    if enable
      Syscall.ioctl(fd, TIOCEXCL, 0)
    else
      Syscall.ioctl(fd, TIOCNXCL, 0)
    end
  end

  def self.exclusive?(fd : Int32) : Bool
    {% if flag?(:darwin) %}
      raise Error.new("Session.exclusive? is Linux-only")
    {% else %}
      value = 0_i32
      Syscall.ioctl(fd, TIOCGEXCL, pointerof(value))
      value != 0
    {% end %}
  end
end
