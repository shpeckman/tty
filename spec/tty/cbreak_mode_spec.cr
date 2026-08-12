# spec/tty/cbreak_mode_spec.cr
require "../spec_helper"

describe TTY::CBreakMode do
  it "disables canonical mode and echo on initialization" do
    master_fd = uninitialized LibC::Int
    slave_fd = uninitialized LibC::Int

    # We create a pseudoterminal to get a valid TTY FileDescriptor
    if LibC.openpty(pointerof(master_fd), pointerof(slave_fd), Pointer(LibC::Char).null, Pointer(Void).null, Pointer(LibC::Winsize).null) == 0
      master = IO::FileDescriptor.new(master_fd)
      slave  = IO::FileDescriptor.new(slave_fd)

      begin
        orig = uninitialized LibC::Termios
        LibC.tcgetattr(slave.fd, pointerof(orig)).should eq(0)

        mode = TTY::CBreakMode.new(slave)

        current = uninitialized LibC::Termios
        LibC.tcgetattr(slave.fd, pointerof(current)).should eq(0)

        flag_type = typeof(current.c_lflag)

        # Verify cbreak settings were applied
        (current.c_lflag & flag_type.new(LibC::ICANON)).should eq(0)
        (current.c_lflag & flag_type.new(LibC::ECHO)).should eq(0)
        current.c_cc[LibC::VMIN].should eq(1)
        current.c_cc[LibC::VTIME].should eq(0)

        mode.restore

        # Verify state was restored
        restored = uninitialized LibC::Termios
        LibC.tcgetattr(slave.fd, pointerof(restored)).should eq(0)
        restored.c_lflag.should eq(orig.c_lflag)
      ensure
        master.close rescue nil
        slave.close rescue nil
      end
    else
      pending!("Could not allocate PTY for test")
    end
  end

  it "restores automatically when using the .open block syntax" do
    master_fd = uninitialized LibC::Int
    slave_fd = uninitialized LibC::Int

    if LibC.openpty(pointerof(master_fd), pointerof(slave_fd), Pointer(LibC::Char).null, Pointer(Void).null, Pointer(LibC::Winsize).null) == 0
      master = IO::FileDescriptor.new(master_fd)
      slave  = IO::FileDescriptor.new(slave_fd)

      begin
        orig = uninitialized LibC::Termios
        LibC.tcgetattr(slave.fd, pointerof(orig)).should eq(0)

        TTY::CBreakMode.open(slave) do |mode|
          current = uninitialized LibC::Termios
          LibC.tcgetattr(slave.fd, pointerof(current))

          flag_type = typeof(current.c_lflag)
          (current.c_lflag & flag_type.new(LibC::ICANON)).should eq(0)

          mode.restored?.should be_false
        end

        restored = uninitialized LibC::Termios
        LibC.tcgetattr(slave.fd, pointerof(restored)).should eq(0)
        restored.c_lflag.should eq(orig.c_lflag)
      ensure
        master.close rescue nil
        slave.close rescue nil
      end
    else
      pending!("Could not allocate PTY for test")
    end
  end
end
