# src/tty/vt/parser.cr
class VT::Parser
  DEFAULT_CAPACITY = 8192

  getter state    : State
  getter capacity : Int32

  @cp      : StaticArray(UInt8, 4)
  @cp_len  : Int32
  @cp_need : Int32

  def initialize(capacity : Int = DEFAULT_CAPACITY)
    @capacity  = capacity.to_i32
    @buffer    = Bytes.new(@capacity)
    @single    = Bytes.new(1)
    @length    = 0
    @truncated = false
    @state     = State::Gnd
    @cp        = StaticArray(UInt8, 4).new(0_u8)
    @cp_len    = 0
    @cp_need   = 0
  end

  def reset : Nil
    @state     = State::Gnd
    @length    = 0
    @truncated = false
    @cp_len    = 0
    @cp_need   = 0
  end

  def parse(data : String) : Array(Token)
    parse(data.to_slice)
  end

  def parse(data : Bytes) : Array(Token)
    tokens = [] of Token
    parse(data) { |token| tokens << token.clone }
    tokens
  end

  def parse(data : String, & : Token ->) : Nil
    parse(data.to_slice) { |token| yield token }
  end

  def parse(data : Bytes, & : Token ->) : Nil
    data.each do |byte|
      if @cp_len > 0 && @state.gnd? && continuation?(byte)
        print_byte(byte) { |token| yield token }
        next
      end

      change = STATE_TABLE.unsafe_fetch(((@state.value.to_i32 - 1) << 8) + byte.to_i32)
      action = Action.new((change & 0xff).to_u8)
      target = (change >> 8).to_u8

      if target == 0
        dispatch(action, byte) { |token| yield token }
      else
        flush_codepoint { |token| yield token }
        dispatch(EXIT_ACTIONS.unsafe_fetch(@state.value.to_i32 - 1), 0_u8) { |token| yield token }
        dispatch(action, byte) { |token| yield token }
        dispatch(ENTRY_ACTIONS.unsafe_fetch(target.to_i32 - 1), byte) { |token| yield token }
        @state = State.new(target)
      end
    end
  end

  def flush : Array(Token)
    tokens = [] of Token
    flush { |token| tokens << token.clone }
    tokens
  end

  def flush(& : Token ->) : Nil
    flush_codepoint { |token| yield token }

    case @state
    when State::CSIEntry, State::CSIParam, State::CSIInter, State::CSIIgnore
      emit_partial(Token::Kind::CSI) { |token| yield token }
    when State::ESC, State::ESCInter
      emit_partial(Token::Kind::ESC) { |token| yield token }
    when State::OSC
      emit_partial(Token::Kind::OSC) { |token| yield token }
    when State::DCSEntry, State::DCSParam, State::DCSInter, State::DCSPass, State::DCSIgnore
      emit_partial(Token::Kind::DCS) { |token| yield token }
    when State::APC
      emit_partial(Token::Kind::APC) { |token| yield token }
    when State::PM
      emit_partial(Token::Kind::PM) { |token| yield token }
    when State::SOS
      emit_partial(Token::Kind::SOS) { |token| yield token }
    end
  end

  private def dispatch(action : Action, byte : UInt8, & : Token ->) : Nil
    case action
    when Action::Print
      print_byte(byte) { |token| yield token }
    when Action::Exec
      flush_codepoint { |token| yield token }
      emit_byte(Token::Kind::C0, byte) { |token| yield token }
    when Action::Seq
      @length    = 0
      @truncated = false
      append(byte)
    when Action::App
      append(byte)
    when Action::ESC
      emit_final(Token::Kind::ESC, byte) { |token| yield token }
    when Action::ESCSS2
      emit_final(Token::Kind::SS2, byte) { |token| yield token }
    when Action::ESCSS3
      emit_final(Token::Kind::SS3, byte) { |token| yield token }
    when Action::C1SS2
      emit_byte(Token::Kind::SS2, byte) { |token| yield token }
    when Action::C1SS3
      emit_byte(Token::Kind::SS3, byte) { |token| yield token }
    when Action::CSI
      emit_final(Token::Kind::CSI, byte) { |token| yield token }
    when Action::DCS
      emit_sequence(Token::Kind::DCS) { |token| yield token }
    when Action::OSC
      emit_sequence(Token::Kind::OSC) { |token| yield token }
    when Action::SOS
      emit_sequence(Token::Kind::SOS) { |token| yield token }
    when Action::PM
      emit_sequence(Token::Kind::PM) { |token| yield token }
    when Action::APC
      emit_sequence(Token::Kind::APC) { |token| yield token }
    end
  end

  private def print_byte(byte : UInt8, & : Token ->) : Nil
    if @cp_len > 0
      if continuation?(byte)
        @cp.unsafe_put(@cp_len, byte)
        @cp_len += 1
        emit_cp(false) { |token| yield token } if @cp_len >= @cp_need
        return
      end
      emit_cp(true) { |token| yield token }
    end

    need = codepoint_length(byte)
    if need == 1
      emit_cp_byte(byte, continuation?(byte)) { |token| yield token }
    else
      @cp.unsafe_put(0, byte)
      @cp_len  = 1
      @cp_need = need
    end
  end

  private def emit_cp(malformed : Bool, & : Token ->) : Nil
    yield Token.new(Token::Kind::Text, @cp.to_slice[0, @cp_len], malformed)
    @cp_len  = 0
    @cp_need = 0
  end

  private def emit_cp_byte(byte : UInt8, malformed : Bool, & : Token ->) : Nil
    @single.unsafe_put(0, byte)
    yield Token.new(Token::Kind::Text, @single, malformed)
  end

  private def flush_codepoint(& : Token ->) : Nil
    emit_cp(true) { |token| yield token } if @cp_len > 0
  end

  private def emit_byte(kind : Token::Kind, byte : UInt8, & : Token ->) : Nil
    @single.unsafe_put(0, byte)
    yield Token.new(kind, @single, false)
  end

  private def emit_final(kind : Token::Kind, byte : UInt8, & : Token ->) : Nil
    append(byte)
    emit_sequence(kind) { |token| yield token }
  end

  private def emit_sequence(kind : Token::Kind, & : Token ->) : Nil
    yield Token.new(kind, @buffer[0, @length], @truncated)
  end

  private def emit_partial(kind : Token::Kind, & : Token ->) : Nil
    yield Token.new(kind, @buffer[0, @length], true) if @length > 0
  end

  private def append(byte : UInt8) : Nil
    if @length < @capacity
      @buffer.unsafe_put(@length, byte)
      @length += 1
    else
      @truncated = true
    end
  end

  private def codepoint_length(byte : UInt8) : Int32
    if byte < 0x80_u8
      1
    elsif byte >= 0xF0_u8
      4
    elsif byte >= 0xE0_u8
      3
    elsif byte >= 0xC2_u8
      2
    else
      1
    end
  end

  private def continuation?(byte : UInt8) : Bool
    (byte & 0xC0_u8) == 0x80_u8
  end
end
