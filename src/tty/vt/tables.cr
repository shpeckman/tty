# src/tty/vt/tables.cr
module VT
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
end
