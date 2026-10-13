# src/tty/control.cr
require "./conversions"
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

  enum FlowAction : Int32
    SuspendOutput = 0
    ResumeOutput  = 1
    SuspendInput  = 2
    ResumeInput   = 3
  end

  struct SerialICount
    getter cts         : Int32
    getter dsr         : Int32
    getter rng         : Int32
    getter dcd         : Int32
    getter rx          : Int32
    getter tx          : Int32
    getter frame       : Int32
    getter overrun     : Int32
    getter parity      : Int32
    getter brk         : Int32
    getter buf_overrun : Int32

    def initialize
      @cts         = 0_i32
      @dsr         = 0_i32
      @rng         = 0_i32
      @dcd         = 0_i32
      @rx          = 0_i32
      @tx          = 0_i32
      @frame       = 0_i32
      @overrun     = 0_i32
      @parity      = 0_i32
      @brk         = 0_i32
      @buf_overrun = 0_i32
    end
  end

  def self.pending_input(fd : Descriptor) : Int32
    count = 0_i32
    Syscall.ioctl(fd_of(fd), TIOCINQ, pointerof(count))
    count
  end

  def self.pending_output(fd : Descriptor) : Int32
    count = 0_i32
    Syscall.ioctl(fd_of(fd), TIOCOUTQ, pointerof(count))
    count
  end

  def self.inject(fd : Descriptor, byte : UInt8) : Nil
    Syscall.ioctl(fd_of(fd), TIOCSTI, pointerof(byte))
  end

  def self.send_break(fd : Descriptor) : Nil
    Syscall.ioctl(fd_of(fd), TIOCSBRK, 0)
  end

  def self.clear_break(fd : Descriptor) : Nil
    Syscall.ioctl(fd_of(fd), TIOCCBRK, 0)
  end

  def self.drain(fd : Descriptor) : Nil
    {% if flag?(:darwin) %}
      Syscall.ioctl(fd_of(fd), TIOCDRAIN, 0)
    {% else %}
      Syscall.ioctl(fd_of(fd), TCSBRK, 1)
    {% end %}
  end

  def self.flow_control(fd : Descriptor, action : FlowAction) : Nil
    {% if flag?(:darwin) %}
      {% raise "TTY.flow_control is Linux-only" %}
    {% else %}
      Syscall.ioctl(fd_of(fd), TCXONC, action.value)
    {% end %}
  end

  def self.modem_status(fd : Descriptor) : ModemLine
    bits = 0_i32
    Syscall.ioctl(fd_of(fd), TIOCMGET, pointerof(bits))
    ModemLine.new(bits)
  end

  def self.set_modem_status(fd : Descriptor, lines : ModemLine) : Nil
    bits = lines.value
    Syscall.ioctl(fd_of(fd), TIOCMSET, pointerof(bits))
  end

  def self.set_modem_lines(fd : Descriptor, lines : ModemLine) : Nil
    {% if flag?(:darwin) %}
      {% raise "TTY.set_modem_lines is Linux-only" %}
    {% else %}
      bits = lines.value
      Syscall.ioctl(fd_of(fd), TIOCMBIS, pointerof(bits))
    {% end %}
  end

  def self.clear_modem_lines(fd : Descriptor, lines : ModemLine) : Nil
    {% if flag?(:darwin) %}
      {% raise "TTY.clear_modem_lines is Linux-only" %}
    {% else %}
      bits = lines.value
      Syscall.ioctl(fd_of(fd), TIOCMBIC, pointerof(bits))
    {% end %}
  end

  def self.wait_modem(fd : Descriptor, lines : ModemLine) : Nil
    {% if flag?(:darwin) %}
      {% raise "TTY.wait_modem is Linux-only" %}
    {% else %}
      Syscall.ioctl(fd_of(fd), TIOCMIWAIT, lines.value.to_u64)
    {% end %}
  end

  def self.serial_icount(fd : Descriptor) : SerialICount
    {% if flag?(:darwin) %}
      {% raise "TTY.serial_icount is Linux-only" %}
    {% else %}
      counts = SerialICount.new
      Syscall.ioctl(fd_of(fd), TIOCGICOUNT, pointerof(counts))
      counts
    {% end %}
  end

  def self.output_empty?(fd : Descriptor) : Bool
    {% if flag?(:darwin) %}
      {% raise "TTY.output_empty? is Linux-only" %}
    {% else %}
      status = 0_i32
      Syscall.ioctl(fd_of(fd), TIOCSERGETLSR, pointerof(status))
      (status & 0x1) != 0
    {% end %}
  end
end
