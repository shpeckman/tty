# spec/tty/interceptor_spec.cr
require "../spec_helper"

class TestInterceptor < TTY::Interceptor
  getter read_data          = IO::Memory.new
  getter write_data         = IO::Memory.new
  getter intercepted_tokens = [] of TTY::Token

  property swallow = false
  property replace_text : String? = nil

  struct CustomMsg
    include MVU::Msg
    getter payload : String

    def initialize(@payload : String)
    end
  end

  def on_pty_read(data : Bytes) : Nil
    @read_data.write(data)
  end

  def on_pty_write(data : Bytes) : Nil
    @write_data.write(data)
  end

  def intercept(token : TTY::Token) : TTY::Token?
    @intercepted_tokens << token
    str = String.new(token.bytes)

    # Test condition for the basic custom trigger
    if str == "Z"
      dispatch(CustomMsg.new("intercepted_custom_event"))
    end

    # Test condition for a custom CSI sequence (e.g. \e[99;<payload>p)
    if token.kind.csi? && str.starts_with?("\e[99;") && str.ends_with?("p")
      payload = str[5..-2]
      dispatch(CustomMsg.new("csi_payload:#{payload}"))
      return nil # Swallow the token
    end

    return nil if @swallow

    if (rep = @replace_text) && token.text?
      return TTY::Token.new(TTY::Token::Kind::Text, rep.to_slice, false)
    end

    token
  end
end

describe TTY::Interceptor do
  it "hooks into pty writes synchronously" do
    interceptor = TestInterceptor.new
    pty         = TTY::PTY.spawn("cat", interceptors: [interceptor] of TTY::Interceptor)

    # We must explicitly run the returned MVU tasks for the I/O to occur in tests
    pty, cmd = pty.update(TTY::Write.new("hello".to_slice))
    cmd.tasks.each &.run.call

    interceptor.write_data.to_s.should eq("hello")

    _, close_cmd = pty.update(TTY::Close.new)
    close_cmd.tasks.each &.run.call
  end

  it "hooks into pty reads and allows dispatching custom messages" do
    interceptor = TestInterceptor.new
    pty         = TTY::PTY.spawn("cat", interceptors: [interceptor] of TTY::Interceptor)

    sub    = pty.subscription(:pty_read)
    cancel = Channel(Nil).new

    # We MUST use a buffered channel in tests to prevent the read fiber
    # from blocking permanently on `send` if the test stops receiving.
    messages = Channel(MVU::Msg).new(100)

    spawn do
      sub.task.call(->(m : MVU::Msg) { messages.send(m) }, cancel)
    end

    # Wait briefly for the task to spin up and bind dispatch
    Fiber.yield

    # Send trigger data to cat, which echoes it back, firing on_pty_read and intercept
    pty, cmd = pty.update(TTY::Write.new("TRIGGER_Z\n".to_slice))
    cmd.tasks.each &.run.call

    custom_received = false
    tokens_received = false

    20.times do
      select
      when msg = messages.receive
        if msg.is_a?(TestInterceptor::CustomMsg)
          msg.payload.should eq("intercepted_custom_event")
          custom_received = true
        elsif msg.is_a?(TTY::TokensDecoded)
          if msg.tokens.any? { |t| String.new(t.bytes) == "Z" }
            tokens_received = true
          end
        end
        break if custom_received && tokens_received
      when timeout(1.second)
        break
      end
    end

    custom_received.should be_true
    tokens_received.should be_true
    interceptor.read_data.to_s.should contain("TRIGGER_Z")
    interceptor.intercepted_tokens.size.should be > 0

    cancel.close
    _, close_cmd = pty.update(TTY::Close.new)
    close_cmd.tasks.each &.run.call
  end

  it "intercepts and swallows custom CSI sequences" do
    interceptor = TestInterceptor.new

    # Use sh and printf to output the exact byte stream without PTY ECHOCTL mangling the ESC character
    pty = TTY::PTY.spawn("sh", ["-c", "printf 'hello\\033[99;12345pworld'"], interceptors: [interceptor] of TTY::Interceptor)

    sub      = pty.subscription(:pty_read)
    cancel   = Channel(Nil).new
    messages = Channel(MVU::Msg).new(100)

    spawn do
      sub.task.call(->(m : MVU::Msg) { messages.send(m) }, cancel)
    end

    custom_received = false
    received_text   = ""

    20.times do
      select
      when msg = messages.receive
        if msg.is_a?(TestInterceptor::CustomMsg)
          msg.payload.should eq("csi_payload:12345")
          custom_received = true
        elsif msg.is_a?(TTY::TokensDecoded)
          msg.tokens.each do |t|
            if t.text?
              received_text += String.new(t.bytes)
            elsif t.kind.csi?
              String.new(t.bytes).should_not contain("\e[99;")
            end
          end
        end
        break if custom_received && received_text.includes?("world")
      when timeout(1.second)
        break
      end
    end

    custom_received.should be_true
    # The CSI sequence should be removed, leaving only the text.
    received_text.should contain("helloworld")

    cancel.close
    _, close_cmd = pty.update(TTY::Close.new)
    close_cmd.tasks.each &.run.call
  end

  it "can modify or swallow intercepted tokens" do
    interceptor = TestInterceptor.new
    interceptor.replace_text = "MODIFIED"
    pty = TTY::PTY.spawn("cat", interceptors: [interceptor] of TTY::Interceptor)

    sub      = pty.subscription(:pty_read)
    cancel   = Channel(Nil).new
    messages = Channel(MVU::Msg).new(100)

    spawn do
      sub.task.call(->(m : MVU::Msg) { messages.send(m) }, cancel)
    end

    Fiber.yield

    pty, cmd = pty.update(TTY::Write.new("target\n".to_slice))
    cmd.tasks.each &.run.call

    found_modified = false
    20.times do
      select
      when msg = messages.receive
        if msg.is_a?(TTY::TokensDecoded)
          if msg.tokens.any? { |t| String.new(t.bytes).includes?("MODIFIED") }
            found_modified = true
            break
          end
        end
      when timeout(1.second)
        break
      end
    end

    found_modified.should be_true

    # Now test swallowing behavior
    interceptor.replace_text = nil
    interceptor.swallow = true

    # Drain any lingering messages safely from the buffered channel
    loop do
      select
      when messages.receive
      else
        break
      end
    end

    pty, cmd = pty.update(TTY::Write.new("ghost\n".to_slice))
    cmd.tasks.each &.run.call

    ghost_found = false
    loop do
      select
      when msg = messages.receive
        if msg.is_a?(TTY::TokensDecoded)
          if msg.tokens.any? { |t| String.new(t.bytes).includes?("ghost") }
            ghost_found = true
          end
        end
      when timeout(200.milliseconds)
        break
      end
    end

    ghost_found.should be_false

    cancel.close
    _, close_cmd = pty.update(TTY::Close.new)
    close_cmd.tasks.each &.run.call
  end
end
