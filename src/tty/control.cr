# src/tty/control.cr
require "./platform"
require "./syscall"

module TTY
  @[Flags]
  enum ModemLine : Int32
    LE  = 0x001
    DTR = 0x002
    RTS = 0x004
    ST  = 0x008
    SR  = 0x010
    CTS = 0x020
    CD  = 0x040
    RI  = 0x080
    DSR = 0x100
  end

  def self.pending_input(fd : Int32) : Int32
    count = 0_i32
    Syscall.ioctl(fd, TIOCINQ, pointerof(count))
    count
  end

  def self.pending_output(fd : Int32) : Int32
    count = 0_i32
    Syscall.ioctl(fd, TIOCOUTQ, pointerof(count))
    count
  end

  def self.inject(fd : Int32, byte : UInt8) : Nil
    Syscall.ioctl(fd, TIOCSTI, pointerof(byte))
  end

  def self.send_break(fd : Int32) : Nil
    Syscall.ioctl(fd, TIOCSBRK, 0)
  end

  def self.clear_break(fd : Int32) : Nil
    Syscall.ioctl(fd, TIOCCBRK, 0)
  end

  def self.modem_status(fd : Int32) : ModemLine
    bits = 0_i32
    Syscall.ioctl(fd, TIOCMGET, pointerof(bits))
    ModemLine.new(bits)
  end

  def self.set_modem_status(fd : Int32, lines : ModemLine) : Nil
    bits = lines.value
    Syscall.ioctl(fd, TIOCMSET, pointerof(bits))
  end
end
