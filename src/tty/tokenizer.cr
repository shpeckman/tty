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

  DEFAULT_STRING_LIMIT = 1 << 20

  @state         : State
  @acc           : IO::Memory
  @kind          : Token::Kind
  @ret_state     : State
  @utf8          : IO::Memory
  @utf8_needed   : Int32
  @string_limit  : Int32
  @string_capped : Bool

  def initialize(@string_limit : Int32 = DEFAULT_STRING_LIMIT)
    @state         = State::Ground
    @acc           = IO::Memory.new
    @kind          = Token::Kind::Text
    @ret_state     = State::Osc
    @utf8          = IO::Memory.new
    @utf8_needed   = 0
    @string_capped = false
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

      if @utf8.size > 0
        index = resume_utf8(data, index, size, tokens)
        next
      end

      start = index

      while index < size
        byte = data.unsafe_fetch(index)
        break if byte == ESC || control_byte?(byte)
        index &+= 1
      end

      if index > start
        emit_text(data[start, index &- start], tokens)
      end

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

  def flush : Array(Token)
    tokens = [] of Token

    if @utf8.size > 0
      tokens << Token.new(Token::Kind::Text, @utf8.to_slice.dup, true)
      @utf8.clear
      @utf8_needed = 0
    end

    case @state
    when State::Esc
      tokens << Token.new(Token::Kind::ESC, Bytes[ESC], true)
    when State::Csi
      tokens << Token.new(Token::Kind::CSI, @acc.to_slice.dup, true) if @acc.size > 0 && !@string_capped
    when State::Osc, State::Dcs, State::Apc, State::Sos, State::Pm
      tokens << Token.new(@kind, @acc.to_slice.dup, true) if @acc.size > 0 && !@string_capped
    when State::StringEsc
      unless @string_capped
        @acc.write_byte(ESC)
        tokens << Token.new(@kind, @acc.to_slice.dup, true)
      end
    end

    @acc.clear
    @state         = State::Ground
    @kind          = Token::Kind::Text
    @string_capped = false

    tokens
  end

  def reset : Nil
    @acc.clear
    @utf8.clear
    @state         = State::Ground
    @kind          = Token::Kind::Text
    @ret_state     = State::Osc
    @utf8_needed   = 0
    @string_capped = false
  end

  private def resume_utf8(data : Bytes, index : Int32, size : Int32, tokens : Array(Token)) : Int32
    while index < size && @utf8.size < @utf8_needed
      byte = data.unsafe_fetch(index)
      break unless continuation_byte?(byte)
      @utf8.write_byte(byte)
      index &+= 1
    end

    if @utf8.size >= @utf8_needed
      emit(Token::Kind::Text, @utf8.to_slice.dup, tokens)
      @utf8.clear
      @utf8_needed = 0
    elsif index < size
      emit(Token::Kind::Text, @utf8.to_slice.dup, tokens, malformed: true)
      @utf8.clear
      @utf8_needed = 0
    end

    index
  end

  private def emit_text(slice : Bytes, tokens : Array(Token)) : Nil
    held = trailing_incomplete(slice)

    if held > 0
      keep = slice.size &- held
      emit(Token::Kind::Text, slice[0, keep].dup, tokens) if keep > 0
      @utf8_needed = utf8_length(slice.unsafe_fetch(keep))
      @utf8.write(slice[keep, held])
    else
      emit(Token::Kind::Text, slice.dup, tokens)
    end
  end

  private def trailing_incomplete(slice : Bytes) : Int32
    size = slice.size
    return 0 if size == 0

    scan  = size &- 1
    limit = size &- 4
    limit = 0 if limit < 0

    while scan >= limit
      byte = slice.unsafe_fetch(scan)

      unless continuation_byte?(byte)
        needed = utf8_length(byte)
        have   = size &- scan
        return needed > have ? have : 0
      end

      scan &-= 1
    end

    0
  end

  private def utf8_length(byte : UInt8) : Int32
    if byte < 0x80_u8
      1
    elsif byte >= 0xF0_u8
      4
    elsif byte >= 0xE0_u8
      3
    elsif byte >= 0xC0_u8
      2
    else
      1
    end
  end

  private def continuation_byte?(byte : UInt8) : Bool
    (byte & 0xC0_u8) == 0x80_u8
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
      @state         = State::Csi
      @string_capped = false
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
    if @string_capped
      if byte >= 0x40_u8 && byte <= 0x7E_u8
        @state         = State::Ground
        @string_capped = false
      end
      return
    end

    @acc.write_byte(byte)

    if byte >= 0x40_u8 && byte <= 0x7E_u8
      emit_acc(Token::Kind::CSI, tokens)
      @state = State::Ground
    elsif @acc.size >= @string_limit
      emit_acc(Token::Kind::CSI, tokens, malformed: true)
      @string_capped = true
    end
  end

  private def enter_string(state : State, kind : Token::Kind, byte : UInt8) : Nil
    @state         = state
    @kind          = kind
    @string_capped = false
    @acc.write_byte(ESC)
    @acc.write_byte(byte)
  end

  private def string_body(byte : UInt8, tokens : Array(Token)) : Nil
    if @string_capped
      if terminates_string?(byte)
        @state         = State::Ground
        @string_capped = false
      elsif byte == ESC
        @ret_state = @state
        @state     = State::StringEsc
      end
      return
    end

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

    if @acc.size >= @string_limit
      emit_acc(@kind, tokens, malformed: true)
      @string_capped = true
    end
  end

  private def string_esc(byte : UInt8, tokens : Array(Token)) : Nil
    if byte == ST
      if @string_capped
        @state         = State::Ground
        @string_capped = false
      else
        @acc.write_byte(ESC)
        @acc.write_byte(byte)
        emit_acc(@kind, tokens)
        @state = State::Ground
      end
      return
    end

    if @string_capped
      @state = @ret_state
      string_body(byte, tokens)
      return
    end

    @acc.write_byte(ESC)
    @state = @ret_state
    string_body(byte, tokens)
  end

  private def emit_acc(kind : Token::Kind, tokens : Array(Token), malformed : Bool = false) : Nil
    bytes = @acc.to_slice.dup
    @acc.clear
    tokens << Token.new(kind, bytes, malformed)
  end

  private def emit(kind : Token::Kind, bytes : Bytes, tokens : Array(Token), malformed : Bool = false) : Nil
    tokens << Token.new(kind, bytes, malformed)
  end

  private def terminates_string?(byte : UInt8) : Bool
    byte == ST || (byte == BEL && @kind.osc?)
  end

  private def control_byte?(byte : UInt8) : Bool
    byte <= 0x1F_u8 || byte == DEL
  end
end
