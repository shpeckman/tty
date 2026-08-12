# src/tty/codec/gfx.cr
require "base64"
require "compress/zlib"
require "../token"

module TTY::Codec::Gfx
  MAX_CHUNK    = 4096
  MIN_CAPACITY = 4352
  MAX_PAYLOAD  = 32 * 1024 * 1024

  NO_DATA = Bytes.empty

  enum Format : Int32
    RGB  =  24
    RGBA =  32
    PNG  = 100
  end

  enum Medium : UInt8
    Direct
    File
    TempFile
    SharedMemory
  end

  enum Compression : UInt8
    None
    Deflate
  end

  enum Quiet : UInt8
    All
    NoOk
    Silent
  end

  enum Blend : UInt8
    Alpha
    Replace
  end

  enum AnimState : UInt8
    Unspecified = 0
    Stop        = 1
    LoadWait    = 2
    Run         = 3
  end

  enum DeleteTarget : UInt8
    All
    Id
    Number
    Cursor
    Frames
    Cell
    CellZ
    IdRange
    Column
    Row
    ZIndex
  end

  enum ErrorCode : UInt8
    EINVAL
    ENOENT
    ENOSPC
    ENOPARENT
    ECYCLE
    ETOODEEP
    EBADF
  end

  struct Id
    getter image_id     : UInt32
    getter image_number : UInt32
    getter placement_id : UInt32

    def self.image(image_id : Int, placement_id : Int = 0) : Id
      new(image_id.to_u32, 0_u32, placement_id.to_u32)
    end

    def self.number(image_number : Int, placement_id : Int = 0) : Id
      new(0_u32, image_number.to_u32, placement_id.to_u32)
    end

    def initialize(@image_id : UInt32 = 0_u32, @image_number : UInt32 = 0_u32, @placement_id : UInt32 = 0_u32)
    end

    def empty? : Bool
      @image_id.zero? && @image_number.zero?
    end
  end

  struct Rect
    getter x      : Int32
    getter y      : Int32
    getter width  : Int32
    getter height : Int32

    def initialize(@x : Int32 = 0, @y : Int32 = 0, @width : Int32 = 0, @height : Int32 = 0)
    end
  end

  struct Source
    getter format      : Format
    getter medium      : Medium
    getter width       : Int32
    getter height      : Int32
    getter size        : Int32
    getter offset      : Int32
    getter compression : Compression
    getter hints       : Int32
    getter payload     : Bytes
    getter? more       : Bool

    def self.png(data : Bytes, compression : Compression = Compression::None) : Source
      new(payload: data, format: Format::PNG, compression: compression)
    end

    def self.rgba(data : Bytes, width : Int32, height : Int32, compression : Compression = Compression::None) : Source
      new(payload: data, format: Format::RGBA, width: width, height: height, compression: compression)
    end

    def self.rgb(data : Bytes, width : Int32, height : Int32, compression : Compression = Compression::None) : Source
      new(payload: data, format: Format::RGB, width: width, height: height, compression: compression)
    end

    def self.file(path : String, format : Format = Format::PNG) : Source
      new(payload: path.to_slice, format: format, medium: Medium::File)
    end

    def self.temp_file(path : String, format : Format = Format::PNG) : Source
      new(payload: path.to_slice, format: format, medium: Medium::TempFile)
    end

    def self.shared(name : String, format : Format = Format::PNG) : Source
      new(payload: name.to_slice, format: format, medium: Medium::SharedMemory)
    end

    def initialize(
      @payload : Bytes = NO_DATA,
      @format : Format = Format::RGBA,
      @medium : Medium = Medium::Direct,
      @width : Int32 = 0,
      @height : Int32 = 0,
      @size : Int32 = 0,
      @offset : Int32 = 0,
      @compression : Compression = Compression::None,
      @hints : Int32 = 0,
      @more : Bool = false,
    )
    end

    def data : Bytes?
      @medium.direct? ? @payload : nil
    end

    def path : String?
      @medium.direct? ? nil : String.new(@payload)
    end

    def with_payload(payload : Bytes) : Source
      Source.new(payload, @format, @medium, @width, @height, @size, @offset, @compression, @hints, false)
    end
  end

  struct Placement
    getter x                : Int32
    getter y                : Int32
    getter width            : Int32
    getter height           : Int32
    getter cell_x           : Int32
    getter cell_y           : Int32
    getter columns          : Int32
    getter rows             : Int32
    getter z                : Int32
    getter parent           : UInt32
    getter parent_placement : UInt32
    getter offset_x         : Int32
    getter offset_y         : Int32
    getter? move_cursor     : Bool
    getter? virtual         : Bool

    def initialize(
      @x : Int32 = 0,
      @y : Int32 = 0,
      @width : Int32 = 0,
      @height : Int32 = 0,
      @cell_x : Int32 = 0,
      @cell_y : Int32 = 0,
      @columns : Int32 = 0,
      @rows : Int32 = 0,
      @z : Int32 = 0,
      @parent : UInt32 = 0_u32,
      @parent_placement : UInt32 = 0_u32,
      @offset_x : Int32 = 0,
      @offset_y : Int32 = 0,
      @move_cursor : Bool = true,
      @virtual : Bool = false,
    )
    end
  end

  struct Frame
    getter x          : Int32
    getter y          : Int32
    getter base       : Int32
    getter edit       : Int32
    getter gap        : Int32
    getter blend      : Blend
    getter background : UInt32

    def initialize(
      @x : Int32 = 0,
      @y : Int32 = 0,
      @base : Int32 = 0,
      @edit : Int32 = 0,
      @gap : Int32 = 0,
      @blend : Blend = Blend::Alpha,
      @background : UInt32 = 0_u32,
    )
    end
  end

  struct Transmit
    getter id        : Id
    getter source    : Source
    getter placement : Placement?
    getter quiet     : Quiet

    def initialize(@id : Id = Id.new, @source : Source = Source.new, @placement : Placement? = nil, @quiet : Quiet = Quiet::All)
    end
  end

  struct Query
    getter id     : Id
    getter source : Source
    getter quiet  : Quiet

    def initialize(@id : Id = Id.new, @source : Source = Source.new, @quiet : Quiet = Quiet::All)
    end
  end

  struct Put
    getter id        : Id
    getter placement : Placement
    getter quiet     : Quiet

    def initialize(@id : Id = Id.new, @placement : Placement = Placement.new, @quiet : Quiet = Quiet::All)
    end
  end

  struct Delete
    getter id         : Id
    getter target     : DeleteTarget
    getter x          : Int32
    getter y          : Int32
    getter z          : Int32
    getter quiet      : Quiet
    getter? free_data : Bool

    def initialize(
      @id : Id = Id.new,
      @target : DeleteTarget = DeleteTarget::All,
      @free_data : Bool = false,
      @x : Int32 = 0,
      @y : Int32 = 0,
      @z : Int32 = 0,
      @quiet : Quiet = Quiet::All,
    )
    end
  end

  struct FrameTransmit
    getter id     : Id
    getter source : Source
    getter frame  : Frame
    getter quiet  : Quiet

    def initialize(@id : Id = Id.new, @source : Source = Source.new, @frame : Frame = Frame.new, @quiet : Quiet = Quiet::All)
    end
  end

  struct Animate
    getter id      : Id
    getter state   : AnimState
    getter frame   : Int32
    getter gap     : Int32
    getter current : Int32
    getter loops   : Int32
    getter quiet   : Quiet

    def initialize(
      @id : Id = Id.new,
      @state : AnimState = AnimState::Unspecified,
      @frame : Int32 = 0,
      @gap : Int32 = 0,
      @current : Int32 = 0,
      @loops : Int32 = 0,
      @quiet : Quiet = Quiet::All,
    )
    end
  end

  struct Compose
    getter id           : Id
    getter source_frame : Int32
    getter target_frame : Int32
    getter source       : Rect
    getter target       : Rect
    getter blend        : Blend
    getter quiet        : Quiet

    def initialize(
      @id : Id = Id.new,
      @source_frame : Int32 = 0,
      @target_frame : Int32 = 0,
      @source : Rect = Rect.new,
      @target : Rect = Rect.new,
      @blend : Blend = Blend::Alpha,
      @quiet : Quiet = Quiet::All,
    )
    end
  end

  alias Command = Transmit | Query | Put | Delete | FrameTransmit | Animate | Compose

  struct Chunk
    getter encoded : Bytes
    getter quiet   : Quiet
    getter? more   : Bool
    getter? frame  : Bool

    def initialize(@encoded : Bytes, @quiet : Quiet = Quiet::All, @more : Bool = false, @frame : Bool = false)
    end

    def decode : Bytes?
      Base64.decode(@encoded)
    rescue
      nil
    end
  end

  struct Response
    getter id      : Id
    getter code    : ErrorCode?
    getter message : String

    def self.ok(id : Id) : Response
      new(id, nil, "")
    end

    def initialize(@id : Id = Id.new, @code : ErrorCode? = nil, @message : String = "")
    end

    def ok? : Bool
      @code.nil?
    end

    def text : String
      code = @code
      return "OK" if code.nil?
      @message.empty? ? code.to_s : "#{code}:#{@message}"
    end

    def suppressed?(quiet : Quiet) : Bool
      ok? ? !quiet.all? : quiet.silent?
    end

    def write_to(io : IO) : Nil
      io << "\e_G"
      control = Control.new(io)
      control.put('i', @id.image_id)
      control.put('I', @id.image_number)
      control.put('p', @id.placement_id)
      io << ';' << text << "\e\\"
    end

    def to_slice : Bytes
      io = IO::Memory.new
      write_to(io)
      io.to_slice
    end

    def to_s(io : IO) : Nil
      write_to(io)
    end
  end

  struct Failure
    getter code : ErrorCode,
      message : String,
      id      : Id,
      quiet   : Quiet

    def initialize(@code : ErrorCode, @message : String = "", @id : Id = Id.new, @quiet : Quiet = Quiet::All)
    end

    def response : Response
      Response.new(@id, @code, @message)
    end
  end

  class Control
    def initialize(@io : IO)
      @first = true
    end

    def put(key : Char, value : Int32, default : Int32 = 0) : Nil
      return if value == default
      force(key, value)
    end

    def put(key : Char, value : UInt32, default : UInt32 = 0_u32) : Nil
      return if value == default
      separator
      @io << key << '=' << value
    end

    def put(key : Char, value : Char) : Nil
      separator
      @io << key << '=' << value
    end

    def force(key : Char, value : Int32) : Nil
      separator
      @io << key << '=' << value
    end

    private def separator : Nil
      @io << ',' unless @first
      @first = false
    end
  end

  private struct Keys
    property k_a : UInt8 = 0x74_u8,
      k_t        : UInt8 = 0x64_u8,
      k_o        : UInt8 = 0_u8,
      k_d        : UInt8 = 0x61_u8,
      k_q        : Int64 = 0_i64,
      k_f        : Int64 = 32_i64,
      k_s        : Int64 = 0_i64,
      k_v        : Int64 = 0_i64,
      k_big_s    : Int64 = 0_i64,
      k_big_o    : Int64 = 0_i64,
      k_i        : Int64 = 0_i64,
      k_big_i    : Int64 = 0_i64,
      k_p        : Int64 = 0_i64,
      k_m        : Int64 = 0_i64,
      k_big_n    : Int64 = 0_i64,
      k_x        : Int64 = 0_i64,
      k_y        : Int64 = 0_i64,
      k_w        : Int64 = 0_i64,
      k_h        : Int64 = 0_i64,
      k_big_x    : Int64 = 0_i64,
      k_big_y    : Int64 = 0_i64,
      k_c        : Int64 = 0_i64,
      k_r        : Int64 = 0_i64,
      k_big_c    : Int64 = 0_i64,
      k_big_u    : Int64 = 0_i64,
      k_z        : Int64 = 0_i64,
      k_big_p    : Int64 = 0_i64,
      k_big_q    : Int64 = 0_i64,
      k_big_h    : Int64 = 0_i64,
      k_big_v    : Int64 = 0_i64,
      has_action : Bool  = false,
      has_id     : Bool  = false,
      has_number : Bool  = false,
      has_more   : Bool  = false,
      extra      : Bool  = false

    def initialize
    end
  end

  def self.command(token : TTY::Token) : Command | Chunk | Failure | Nil
    body = body_of(token)
    return nil if body.nil?

    separator = body.index(0x3b_u8)
    control   = separator ? body[0, separator] : body
    encoded   = separator ? body[separator + 1, body.size - separator - 1] : NO_DATA

    parsed = parse_keys(control)
    return Failure.new(ErrorCode::EINVAL, "invalid control data") if parsed.is_a?(ErrorCode)

    keys  = parsed
    id    = Id.new(narrow_u(keys.k_i), narrow_u(keys.k_big_i), narrow_u(keys.k_p))
    quiet = Quiet.from_value?(narrow(keys.k_q)) || Quiet::All

    return Chunk.new(encoded, quiet, keys.k_m == 1_i64, keys.k_a == 0x66_u8) if chunk?(keys)

    if keys.has_id && keys.has_number
      return Failure.new(ErrorCode::EINVAL, "i and I are mutually exclusive", id, quiet)
    end

    payload = decode_payload(encoded)
    return Failure.new(ErrorCode::EINVAL, "invalid base64 payload", id, quiet) if payload.nil?

    case keys.k_a.unsafe_chr
    when 't'
      source = build_source(keys, payload, id, quiet)
      source.is_a?(Failure) ? source : Transmit.new(id, source, nil, quiet)
    when 'T'
      source = build_source(keys, payload, id, quiet)
      source.is_a?(Failure) ? source : Transmit.new(id, source, build_placement(keys), quiet)
    when 'q'
      source = build_source(keys, payload, id, quiet)
      source.is_a?(Failure) ? source : Query.new(id, source, quiet)
    when 'p'
      Put.new(id, build_placement(keys), quiet)
    when 'd'
      selector = delete_target(keys.k_d)
      return Failure.new(ErrorCode::EINVAL, "unknown delete selector", id, quiet) if selector.nil?
      target, free = selector
      Delete.new(id, target, free, narrow(keys.k_x), narrow(keys.k_y), narrow(keys.k_z), quiet)
    when 'f'
      source = build_source(keys, payload, id, quiet)
      source.is_a?(Failure) ? source : FrameTransmit.new(id, source, build_frame(keys), quiet)
    when 'a'
      state = AnimState.from_value?(narrow(keys.k_s))
      return Failure.new(ErrorCode::EINVAL, "unknown animation state", id, quiet) if state.nil?
      Animate.new(id, state, narrow(keys.k_r), narrow(keys.k_z), narrow(keys.k_c), narrow(keys.k_v), quiet)
    when 'c'
      width  = narrow(keys.k_w)
      height = narrow(keys.k_h)
      Compose.new(
        id,
        narrow(keys.k_r),
        narrow(keys.k_c),
        Rect.new(narrow(keys.k_big_x), narrow(keys.k_big_y), width, height),
        Rect.new(narrow(keys.k_x), narrow(keys.k_y), width, height),
        keys.k_big_c.zero? ? Blend::Alpha : Blend::Replace,
        quiet
      )
    else
      Failure.new(ErrorCode::EINVAL, "unknown action", id, quiet)
    end
  end

  def self.response(token : TTY::Token) : Response?
    body = body_of(token)
    return nil if body.nil?

    separator = body.index(0x3b_u8)
    return nil if separator.nil?

    parsed = parse_keys(body[0, separator])
    return nil if parsed.is_a?(ErrorCode)
    return nil if parsed.has_action

    id   = Id.new(narrow_u(parsed.k_i), narrow_u(parsed.k_big_i), narrow_u(parsed.k_p))
    text = String.new(body[separator + 1, body.size - separator - 1])

    return Response.ok(id) if text == "OK"

    head, _, rest = text.partition(':')
    code = ErrorCode.parse?(head)
    return nil if code.nil?

    Response.new(id, code, rest)
  end

  def self.source_of(command : Command) : Source?
    case command
    in Transmit, Query, FrameTransmit then command.source
    in Put, Delete, Animate, Compose  then nil
    end
  end

  def self.inflate(data : Bytes) : Bytes?
    output = IO::Memory.new
    Compress::Zlib::Reader.open(IO::Memory.new(data)) { |reader| IO.copy(reader, output) }
    output.to_slice
  rescue
    nil
  end

  def self.deflate(data : Bytes) : Bytes
    output = IO::Memory.new
    Compress::Zlib::Writer.open(output) { |writer| writer.write(data) }
    output.to_slice
  end

  def self.encode(command : Command, chunk_size : Int32 = MAX_CHUNK, & : Bytes ->) : Nil
    limit   = chunk_size < 4 ? 4 : (chunk_size >> 2) << 2
    source  = source_of(command)
    encoded = source ? encode_payload(source) : NO_DATA

    if encoded.size <= limit
      yield build(command, encoded, true, false, false)
      return
    end

    offset = 0
    first  = true

    while offset < encoded.size
      taken = Math.min(limit, encoded.size - offset)
      slice = encoded[offset, taken]
      offset += taken
      yield build(command, slice, first, true, offset < encoded.size)
      first = false
    end
  end

  def self.encode(command : Command, io : IO, chunk_size : Int32 = MAX_CHUNK) : Nil
    encode(command, chunk_size) { |chunk| io.write(chunk) }
  end

  def self.encode(command : Command, chunk_size : Int32 = MAX_CHUNK) : Array(Bytes)
    chunks = [] of Bytes
    encode(command, chunk_size) { |chunk| chunks << chunk }
    chunks
  end

  private def self.build(command : Command, payload : Bytes, first : Bool, chunked : Bool, more : Bool) : Bytes
    io = IO::Memory.new
    io << "\e_G"

    control = Control.new(io)

    if first
      write_control(command, control)
    else
      control.put('a', 'f') if command.is_a?(FrameTransmit)
      control.put('q', command.quiet.value.to_i32)
    end

    control.force('m', more ? 1 : 0) if chunked

    unless payload.empty?
      io << ';'
      io.write(payload)
    end

    io << "\e\\"
    io.to_slice
  end

  private def self.write_control(command : Command, control : Control) : Nil
    case command
    in Transmit
      control.put('a', command.placement ? 'T' : 't')
      write_id(control, command.id)
      write_source(control, command.source)
      if placement = command.placement
        write_placement(control, placement)
      end
    in Query
      control.put('a', 'q')
      write_id(control, command.id)
      write_source(control, command.source)
    in Put
      control.put('a', 'p')
      write_id(control, command.id)
      write_placement(control, command.placement)
    in Delete
      control.put('a', 'd')
      control.put('d', delete_letter(command.target, command.free_data?))
      write_id(control, command.id)
      control.put('x', command.x)
      control.put('y', command.y)
      control.put('z', command.z)
    in FrameTransmit
      control.put('a', 'f')
      write_id(control, command.id)
      write_source(control, command.source)
      write_frame(control, command.frame)
    in Animate
      control.put('a', 'a')
      write_id(control, command.id)
      control.put('s', command.state.value.to_i32)
      control.put('r', command.frame)
      control.put('z', command.gap)
      control.put('c', command.current)
      control.put('v', command.loops)
    in Compose
      control.put('a', 'c')
      write_id(control, command.id)
      control.put('c', command.target_frame)
      control.put('r', command.source_frame)
      control.put('x', command.target.x)
      control.put('y', command.target.y)
      control.put('w', command.target.width)
      control.put('h', command.target.height)
      control.put('X', command.source.x)
      control.put('Y', command.source.y)
      control.put('C', command.blend.value.to_i32)
    end

    control.put('q', command.quiet.value.to_i32)
  end

  private def self.write_id(control : Control, id : Id) : Nil
    control.put('i', id.image_id)
    control.put('I', id.image_number)
    control.put('p', id.placement_id)
  end

  private def self.write_source(control : Control, source : Source) : Nil
    control.put('f', source.format.value, Format::RGBA.value)
    control.put('t', medium_letter(source.medium)) unless source.medium.direct?
    control.put('s', source.width)
    control.put('v', source.height)
    control.put('S', source.size)
    control.put('O', source.offset)
    control.put('o', 'z') if source.compression.deflate?
    control.put('N', source.hints)
  end

  private def self.write_placement(control : Control, placement : Placement) : Nil
    control.put('x', placement.x)
    control.put('y', placement.y)
    control.put('w', placement.width)
    control.put('h', placement.height)
    control.put('X', placement.cell_x)
    control.put('Y', placement.cell_y)
    control.put('c', placement.columns)
    control.put('r', placement.rows)
    control.put('C', 1) unless placement.move_cursor?
    control.put('U', 1) if placement.virtual?
    control.put('z', placement.z)
    control.put('P', placement.parent)
    control.put('Q', placement.parent_placement)
    control.put('H', placement.offset_x)
    control.put('V', placement.offset_y)
  end

  private def self.write_frame(control : Control, frame : Frame) : Nil
    control.put('x', frame.x)
    control.put('y', frame.y)
    control.put('c', frame.base)
    control.put('r', frame.edit)
    control.put('z', frame.gap)
    control.put('X', frame.blend.value.to_i32)
    control.put('Y', frame.background)
  end

  private def self.encode_payload(source : Source) : Bytes
    data = source.payload
    data = deflate(data) if source.medium.direct? && source.compression.deflate?
    Base64.strict_encode(data).to_slice
  end

  private def self.medium_letter(medium : Medium) : Char
    case medium
    in Medium::Direct       then 'd'
    in Medium::File         then 'f'
    in Medium::TempFile     then 't'
    in Medium::SharedMemory then 's'
    end
  end

  private def self.delete_letter(target : DeleteTarget, free : Bool) : Char
    letter = case target
             in DeleteTarget::All     then 'a'
             in DeleteTarget::Id      then 'i'
             in DeleteTarget::Number  then 'n'
             in DeleteTarget::Cursor  then 'c'
             in DeleteTarget::Frames  then 'f'
             in DeleteTarget::Cell    then 'p'
             in DeleteTarget::CellZ   then 'q'
             in DeleteTarget::IdRange then 'r'
             in DeleteTarget::Column  then 'x'
             in DeleteTarget::Row     then 'y'
             in DeleteTarget::ZIndex  then 'z'
             end
    free ? letter.upcase : letter
  end

  private def self.delete_target(letter : UInt8) : {DeleteTarget, Bool}?
    character = letter.unsafe_chr
    free      = character >= 'A' && character <= 'Z'

    target = case character.downcase
             when 'a' then DeleteTarget::All
             when 'i' then DeleteTarget::Id
             when 'n' then DeleteTarget::Number
             when 'c' then DeleteTarget::Cursor
             when 'f' then DeleteTarget::Frames
             when 'p' then DeleteTarget::Cell
             when 'q' then DeleteTarget::CellZ
             when 'r' then DeleteTarget::IdRange
             when 'x' then DeleteTarget::Column
             when 'y' then DeleteTarget::Row
             when 'z' then DeleteTarget::ZIndex
             end

    return nil if target.nil?
    {target, free}
  end

  private def self.build_source(keys : Keys, payload : Bytes, id : Id, quiet : Quiet) : Source | Failure
    format = Format.from_value?(narrow(keys.k_f))
    return Failure.new(ErrorCode::EINVAL, "unsupported image format", id, quiet) if format.nil?

    medium = case keys.k_t.unsafe_chr
             when 'd' then Medium::Direct
             when 'f' then Medium::File
             when 't' then Medium::TempFile
             when 's' then Medium::SharedMemory
             end
    return Failure.new(ErrorCode::EINVAL, "unsupported transmission medium", id, quiet) if medium.nil?

    compression = case keys.k_o
                  when    0_u8 then Compression::None
                  when 0x7a_u8 then Compression::Deflate
                  end
    return Failure.new(ErrorCode::EINVAL, "unsupported compression", id, quiet) if compression.nil?

    more = keys.k_m == 1_i64
    data = payload

    if !more && medium.direct? && compression.deflate?
      inflated = inflate(payload)
      return Failure.new(ErrorCode::EINVAL, "invalid deflate stream", id, quiet) if inflated.nil?
      data = inflated
    end

    Source.new(
      data,
      format,
      medium,
      narrow(keys.k_s),
      narrow(keys.k_v),
      narrow(keys.k_big_s),
      narrow(keys.k_big_o),
      compression,
      narrow(keys.k_big_n),
      more
    )
  end

  private def self.build_placement(keys : Keys) : Placement
    Placement.new(
      narrow(keys.k_x),
      narrow(keys.k_y),
      narrow(keys.k_w),
      narrow(keys.k_h),
      narrow(keys.k_big_x),
      narrow(keys.k_big_y),
      narrow(keys.k_c),
      narrow(keys.k_r),
      narrow(keys.k_z),
      narrow_u(keys.k_big_p),
      narrow_u(keys.k_big_q),
      narrow(keys.k_big_h),
      narrow(keys.k_big_v),
      keys.k_big_c.zero?,
      keys.k_big_u == 1_i64
    )
  end

  private def self.build_frame(keys : Keys) : Frame
    Frame.new(
      narrow(keys.k_x),
      narrow(keys.k_y),
      narrow(keys.k_c),
      narrow(keys.k_r),
      narrow(keys.k_z),
      keys.k_big_x.zero? ? Blend::Alpha : Blend::Replace,
      narrow_u(keys.k_big_y)
    )
  end

  private def self.chunk?(keys : Keys) : Bool
    return false unless keys.has_more
    return false if keys.extra
    return true unless keys.has_action
    keys.k_a == 0x66_u8
  end

  private def self.decode_payload(encoded : Bytes) : Bytes?
    return NO_DATA if encoded.empty?
    Base64.decode(encoded)
  rescue
    nil
  end

  private def self.body_of(token : TTY::Token) : Bytes?
    return nil unless token.kind.apc?
    return nil if token.malformed?

    bytes = token.bytes

    offset = if bytes.size >= 2 && bytes.unsafe_fetch(0) == 0x1b_u8 && bytes.unsafe_fetch(1) == 0x5f_u8
               2
             elsif bytes.size >= 1 && bytes.unsafe_fetch(0) == 0x9f_u8
               1
             else
               return nil
             end

    return nil unless bytes.size > offset && bytes.unsafe_fetch(offset) == 0x47_u8
    bytes[offset + 1, bytes.size - offset - 1]
  end

  private def self.parse_keys(control : Bytes) : Keys | ErrorCode
    keys  = Keys.new
    index = 0
    size  = control.size

    while index < size
      key = control.unsafe_fetch(index)
      index += 1

      return ErrorCode::EINVAL unless index < size && control.unsafe_fetch(index) == 0x3d_u8
      index += 1

      character = key.unsafe_chr

      case character
      when 'a', 't', 'o', 'd'
        return ErrorCode::EINVAL unless index < size
        letter = control.unsafe_fetch(index)
        index += 1

        case character
        when 'a'
          keys.k_a = letter
          keys.has_action = true
        when 't'
          keys.k_t = letter
          keys.extra = true
        when 'o'
          keys.k_o = letter
          keys.extra = true
        when 'd'
          keys.k_d = letter
          keys.extra = true
        end
      else
        negative = false

        if index < size && control.unsafe_fetch(index) == 0x2d_u8
          negative = true
          index += 1
        end

        value  = 0_i64
        digits = 0

        while index < size
          digit = control.unsafe_fetch(index)
          break if digit < 0x30_u8 || digit > 0x39_u8
          return ErrorCode::EINVAL if digits >= 12
          value = value &* 10_i64 &+ (digit - 0x30_u8).to_i64
          digits += 1
          index += 1
        end

        return ErrorCode::EINVAL if digits.zero?
        value = -value if negative

        keys.extra = true unless character == 'm' || character == 'q'

        case character
        when 'q' then keys.k_q = value
        when 'f' then keys.k_f = value
        when 's' then keys.k_s = value
        when 'v' then keys.k_v = value
        when 'S' then keys.k_big_s = value
        when 'O' then keys.k_big_o = value
        when 'i'
          keys.k_i = value
          keys.has_id = true
        when 'I'
          keys.k_big_i = value
          keys.has_number = true
        when 'p' then keys.k_p = value
        when 'm'
          keys.k_m = value
          keys.has_more = true
        when 'N' then keys.k_big_n = value
        when 'x' then keys.k_x = value
        when 'y' then keys.k_y = value
        when 'w' then keys.k_w = value
        when 'h' then keys.k_h = value
        when 'X' then keys.k_big_x = value
        when 'Y' then keys.k_big_y = value
        when 'c' then keys.k_c = value
        when 'r' then keys.k_r = value
        when 'C' then keys.k_big_c = value
        when 'U' then keys.k_big_u = value
        when 'z' then keys.k_z = value
        when 'P' then keys.k_big_p = value
        when 'Q' then keys.k_big_q = value
        when 'H' then keys.k_big_h = value
        when 'V' then keys.k_big_v = value
        end
      end

      if index < size
        return ErrorCode::EINVAL unless control.unsafe_fetch(index) == 0x2c_u8
        index += 1
        return ErrorCode::EINVAL if index >= size
      end
    end

    keys
  end

  private def self.narrow(value : Int64) : Int32
    return Int32::MAX if value > Int32::MAX
    return Int32::MIN if value < Int32::MIN
    value.to_i32
  end

  private def self.narrow_u(value : Int64) : UInt32
    return 0_u32 if value < 0
    return UInt32::MAX if value > UInt32::MAX
    value.to_u32
  end

  class Assembler
    getter max_payload : Int32

    @pending   : Command?
    @data      : IO::Memory
    @scratch   : IO::Memory
    @carry     : StaticArray(UInt8, 4)
    @carry_len : Int32

    def initialize(@max_payload : Int32 = MAX_PAYLOAD)
      @pending   = nil
      @data      = IO::Memory.new
      @scratch   = IO::Memory.new
      @carry     = StaticArray(UInt8, 4).new(0_u8)
      @carry_len = 0
    end

    def pending? : Bool
      !@pending.nil?
    end

    def reset : Nil
      @pending   = nil
      @carry_len = 0
      @data.clear
    end

    def feed(token : TTY::Token) : Command | Failure | Nil
      decoded = Gfx.command(token)
      return nil if decoded.nil?

      if decoded.is_a?(Failure)
        reset
        return decoded
      end

      return absorb(decoded) if decoded.is_a?(Chunk)

      start(decoded)
    end

    private def start(command : Command) : Command | Failure | Nil
      reset

      source = Gfx.source_of(command)
      return command if source.nil? || !source.more?

      return quota(command) if overflow?(source.payload.size)

      @pending = command
      @data.write(source.payload)
      nil
    end

    private def absorb(chunk : Chunk) : Command | Failure | Nil
      pending = @pending
      return nil if pending.nil?

      failure = push(chunk.encoded, pending)
      return failure if failure

      return nil if chunk.more?

      finish(pending)
    end

    private def push(encoded : Bytes, pending : Command) : Failure?
      @scratch.clear
      @carry_len.times { |index| @scratch.write_byte(@carry.unsafe_fetch(index)) }
      encoded.each { |byte| @scratch.write_byte(byte) if byte > 0x20_u8 }

      filtered = @scratch.to_slice
      usable   = (filtered.size >> 2) << 2

      @carry_len = filtered.size - usable
      @carry_len.times { |index| @carry.unsafe_put(index, filtered.unsafe_fetch(usable + index)) }

      return nil if usable.zero?

      bytes = begin
        Base64.decode(filtered[0, usable])
      rescue
        reset
        return Failure.new(ErrorCode::EINVAL, "invalid base64 payload", pending.id, pending.quiet)
      end

      return quota(pending) if overflow?(bytes.size)

      @data.write(bytes)
      nil
    end

    private def finish(pending : Command) : Command | Failure
      if @carry_len > 0
        tail = begin
          Base64.decode(Bytes.new(@carry.to_unsafe, @carry_len))
        rescue
          reset
          return Failure.new(ErrorCode::EINVAL, "invalid base64 payload", pending.id, pending.quiet)
        end

        return quota(pending) if overflow?(tail.size)
        @data.write(tail)
      end

      data = @data.to_slice.dup
      reset
      rebuild(pending, data)
    end

    private def rebuild(pending : Command, data : Bytes) : Command | Failure
      case pending
      in Transmit
        source = complete(pending.source, data, pending.id, pending.quiet)
        source.is_a?(Failure) ? source : Transmit.new(pending.id, source, pending.placement, pending.quiet)
      in Query
        source = complete(pending.source, data, pending.id, pending.quiet)
        source.is_a?(Failure) ? source : Query.new(pending.id, source, pending.quiet)
      in FrameTransmit
        source = complete(pending.source, data, pending.id, pending.quiet)
        source.is_a?(Failure) ? source : FrameTransmit.new(pending.id, source, pending.frame, pending.quiet)
      in Put, Delete, Animate, Compose
        pending
      end
    end

    private def complete(source : Source, data : Bytes, id : Id, quiet : Quiet) : Source | Failure
      payload = data

      if source.medium.direct? && source.compression.deflate?
        inflated = Gfx.inflate(data)
        return Failure.new(ErrorCode::EINVAL, "invalid deflate stream", id, quiet) if inflated.nil?
        payload = inflated
      end

      source.with_payload(payload)
    end

    private def quota(command : Command) : Failure
      reset
      Failure.new(ErrorCode::ENOSPC, "image data exceeds assembler quota", command.id, command.quiet)
    end

    private def overflow?(size : Int32) : Bool
      @data.size + size > @max_payload
    end
  end
end
