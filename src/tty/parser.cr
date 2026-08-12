# src/tty/parser.cr
require "./token"

module VT
  alias Token = TTY::Token

  enum State : UInt8
    APC       =  1
    CSIEntry  =  2
    CSIIgnore =  3
    CSIInter  =  4
    CSIParam  =  5
    DCSEntry  =  6
    DCSIgnore =  7
    DCSInter  =  8
    DCSParam  =  9
    DCSPass   = 10
    ESC       = 11
    ESCInter  = 12
    Gnd       = 13
    OSC       = 14
    PM        = 15
    SOS       = 16
  end

  enum Action : UInt8
    None   =  0
    APC    =  1
    App    =  2
    C1SS2  =  3
    C1SS3  =  4
    CSI    =  5
    DCS    =  6
    ESC    =  7
    ESCSS2 =  8
    ESCSS3 =  9
    Exec   = 10
    Ignore = 11
    OSC    = 12
    PM     = 13
    Print  = 14
    Seq    = 15
    SOS    = 16
    Error  = 17
  end

  private alias A = Action
  private alias S = State

  alias Rule = Tuple(Range(Int32, Int32), Action, State?)

  STATE_COUNT = State.values.size

  C0_EXEC = [
    {(0..31),  A::Exec, nil},
    {(24..24), A::Exec, S::Gnd},
    {(26..26), A::Exec, S::Gnd},
    {(27..27), A::Seq,  S::ESC},
  ] of Rule

  C0_IGNORE = [
    {(0..31),  A::Ignore, nil},
    {(24..24), A::Exec,   S::Gnd},
    {(26..26), A::Exec,   S::Gnd},
    {(27..27), A::Seq,    S::ESC},
  ] of Rule

  C0_APP = [
    {(0..31),  A::App,  nil},
    {(24..24), A::Exec, S::Gnd},
    {(26..26), A::Exec, S::Gnd},
    {(27..27), A::Seq,  S::ESC},
  ] of Rule

  ANYWHERE = [
    {(128..141), A::Exec,  S::Gnd},
    {(142..142), A::C1SS2, S::Gnd},
    {(143..143), A::C1SS3, S::Gnd},
    {(144..144), A::Seq,   S::DCSEntry},
    {(145..151), A::Exec,  S::Gnd},
    {(152..152), A::Seq,   S::SOS},
    {(153..154), A::Exec,  S::Gnd},
    {(155..155), A::Seq,   S::CSIEntry},
    {(156..156), A::None,  S::Gnd},
    {(157..157), A::Seq,   S::OSC},
    {(158..158), A::Seq,   S::PM},
    {(159..159), A::Seq,   S::APC},
  ] of Rule

  TRANSITIONS = {
    S::APC => C0_APP + ([
      {(32..127), A::App, nil},
    ] of Rule) + ANYWHERE,

    S::CSIEntry => C0_EXEC + ([
      {(32..47),   A::App,    S::CSIInter},
      {(48..63),   A::App,    S::CSIParam},
      {(64..126),  A::CSI,    S::Gnd},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::CSIIgnore => C0_EXEC + ([
      {(32..63),   A::Ignore, nil},
      {(64..126),  A::None,   S::Gnd},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::CSIInter => C0_EXEC + ([
      {(32..47),   A::App,    nil},
      {(48..63),   A::None,   S::CSIIgnore},
      {(64..126),  A::CSI,    S::Gnd},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::CSIParam => C0_EXEC + ([
      {(32..47),   A::App,    S::CSIInter},
      {(48..63),   A::App,    nil},
      {(64..126),  A::CSI,    S::Gnd},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::DCSEntry => C0_IGNORE + ([
      {(32..47),   A::App,    S::DCSInter},
      {(48..63),   A::App,    S::DCSParam},
      {(64..126),  A::App,    S::DCSPass},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::DCSIgnore => C0_IGNORE + ([
      {(32..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::DCSInter => C0_IGNORE + ([
      {(32..47),   A::App,    nil},
      {(48..63),   A::None,   S::DCSIgnore},
      {(64..126),  A::App,    S::DCSPass},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::DCSParam => C0_IGNORE + ([
      {(32..47),   A::App,    S::DCSInter},
      {(48..63),   A::App,    nil},
      {(64..126),  A::App,    S::DCSPass},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::DCSPass => C0_APP + ([
      {(32..126),  A::App,    nil},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::ESC => C0_EXEC + ([
      {(32..47),   A::App,    S::ESCInter},
      {(48..126),  A::ESC,    S::Gnd},
      {(78..78),   A::ESCSS2, S::Gnd},
      {(79..79),   A::ESCSS3, S::Gnd},
      {(80..80),   A::App,    S::DCSEntry},
      {(88..88),   A::App,    S::SOS},
      {(91..91),   A::App,    S::CSIEntry},
      {(92..92),   A::None,   S::Gnd},
      {(93..93),   A::App,    S::OSC},
      {(94..94),   A::App,    S::PM},
      {(95..95),   A::App,    S::APC},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::ESCInter => C0_EXEC + ([
      {(32..47),   A::App,    nil},
      {(48..126),  A::ESC,    S::Gnd},
      {(127..127), A::Ignore, nil},
    ] of Rule) + ANYWHERE,

    S::Gnd => C0_EXEC + ([
      {(32..127),  A::Print, nil},
      {(160..255), A::Print, nil},
    ] of Rule) + ANYWHERE,

    S::OSC => C0_IGNORE + ([
      {(7..7),    A::Ignore, S::Gnd},
      {(32..127), A::App,    nil},
    ] of Rule) + ANYWHERE,

    S::PM => C0_APP + ([
      {(32..127), A::App, nil},
    ] of Rule) + ANYWHERE,

    S::SOS => C0_APP + ([
      {(32..127), A::App, nil},
    ] of Rule) + ANYWHERE,
  }

  def self.build_table : Slice(UInt16)
    table = Slice(UInt16).new(STATE_COUNT * 256, 0_u16)

    TRANSITIONS.each do |state, rules|
      offset = (state.value.to_i32 - 1) * 256

      rules.each do |rule|
        range, action, target = rule
        change = action.value.to_u16
        change |= target.value.to_u16 << 8 if target
        range.each { |byte| table[offset + byte] = change }
      end
    end

    table
  end

  def self.build_actions(actions : Hash(State, Action)) : Slice(Action)
    table = Slice(Action).new(STATE_COUNT, Action::None)
    actions.each { |state, action| table[state.value.to_i32 - 1] = action }
    table
  end

  STATE_TABLE = build_table

  ENTRY_ACTIONS = build_actions(Hash(State, Action).new)

  EXIT_ACTIONS = build_actions({
    S::APC     => A::APC,
    S::DCSPass => A::DCS,
    S::OSC     => A::OSC,
    S::PM      => A::PM,
    S::SOS     => A::SOS,
  })

  class Parser
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
end
