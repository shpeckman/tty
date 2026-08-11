# src/tty/tokenizer.cr
require "./token"

class TTY::Tokenizer
  private enum State
    Ground
    Esc
    Csi
    Osc
    Dcs
    Apc
    Sos
    Pm
    StringEsc
  end

  ESC = 0x1B_u8
  BEL = 0x07_u8
  DEL = 0x7F_u8
  ST  = 0x5C_u8

  @state     : State
  @acc       : IO::Memory
  @kind      : Token::Kind
  @ret_state : State

  def initialize
    @state     = State::Ground
    @acc       = IO::Memory.new
    @kind      = Token::Kind::Text
    @ret_state = State::Osc
  end

  def feed(data : Bytes) : Array(Token)
    tokens = [] of Token
    index  = 0
    size   = data.size

    while index < size
      unless @state.ground?
        step(data.unsafe_fetch(index), tokens)
        index &+= 1
        next
      end

      start = index

      while index < size
        byte = data.unsafe_fetch(index)
        break if byte == ESC || control_byte?(byte)
        index &+= 1
      end

      emit(Token::Kind::Text, data[start, index &- start].dup, tokens) if index > start

      break if index >= size

      byte = data.unsafe_fetch(index)
      index &+= 1

      if byte == ESC
        @state = State::Esc
      else
        emit(Token::Kind::C0, Bytes[byte], tokens)
      end
    end

    tokens
  end

  def reset : Nil
    @acc.clear
    @state     = State::Ground
    @kind      = Token::Kind::Text
    @ret_state = State::Osc
  end

  private def step(byte : UInt8, tokens : Array(Token)) : Nil
    case @state
    when State::Esc
      esc(byte, tokens)
    when State::Csi
      csi(byte, tokens)
    when State::Osc, State::Dcs, State::Apc, State::Sos, State::Pm
      string_body(byte, tokens)
    when State::StringEsc
      string_esc(byte, tokens)
    end
  end

  private def esc(byte : UInt8, tokens : Array(Token)) : Nil
    case byte
    when '['.ord
      @state = State::Csi
      @acc.write_byte(ESC)
      @acc.write_byte(byte)
    when ']'.ord
      enter_string(State::Osc, Token::Kind::OSC, byte)
    when 'P'.ord
      enter_string(State::Dcs, Token::Kind::DCS, byte)
    when '^'.ord
      enter_string(State::Apc, Token::Kind::APC, byte)
    when 'X'.ord
      enter_string(State::Sos, Token::Kind::SOS, byte)
    when '_'.ord
      enter_string(State::Pm, Token::Kind::PM, byte)
    when 'N'.ord
      emit(Token::Kind::SS2, Bytes[ESC, byte], tokens)
      @state = State::Ground
    when 'O'.ord
      emit(Token::Kind::SS3, Bytes[ESC, byte], tokens)
      @state = State::Ground
    else
      emit(Token::Kind::ESC, Bytes[ESC, byte], tokens)
      @state = State::Ground
    end
  end

  private def csi(byte : UInt8, tokens : Array(Token)) : Nil
    @acc.write_byte(byte)
    if byte >= 0x40_u8 && byte <= 0x7E_u8
      emit_acc(Token::Kind::CSI, tokens)
      @state = State::Ground
    end
  end

  private def enter_string(state : State, kind : Token::Kind, byte : UInt8) : Nil
    @state = state
    @kind  = kind
    @acc.write_byte(ESC)
    @acc.write_byte(byte)
  end

  private def string_body(byte : UInt8, tokens : Array(Token)) : Nil
    if byte == BEL && @kind.osc?
      @acc.write_byte(byte)
      emit_acc(@kind, tokens)
      @state = State::Ground
      return
    end

    if byte == ESC
      @ret_state = @state
      @state     = State::StringEsc
      return
    end

    @acc.write_byte(byte)
  end

  private def string_esc(byte : UInt8, tokens : Array(Token)) : Nil
    if byte == ST
      @acc.write_byte(ESC)
      @acc.write_byte(byte)
      emit_acc(@kind, tokens)
      @state = State::Ground
      return
    end

    @acc.write_byte(ESC)
    @state = @ret_state
    step(byte, tokens)
  end

  private def emit_acc(kind : Token::Kind, tokens : Array(Token)) : Nil
    bytes = @acc.to_slice.dup
    @acc.clear
    tokens << Token.new(kind, bytes)
  end

  private def emit(kind : Token::Kind, bytes : Bytes, tokens : Array(Token)) : Nil
    tokens << Token.new(kind, bytes)
  end

  private def control_byte?(byte : UInt8) : Bool
    byte <= 0x1F_u8 || byte == DEL
  end
end
