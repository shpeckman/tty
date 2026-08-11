# src/tty/gfx.cr
require "base64"
require "compress/zlib"
require "random/secure"
require "./token"
require "./tokenizer"

{% if flag?(:linux) %}
  @[Link("rt")]
  lib LibShm
    fun shm_open(name : UInt8*, oflag : Int32, mode : LibC::ModeT) : Int32
    fun shm_unlink(name : UInt8*) : Int32
    fun ftruncate(fd : Int32, length : LibC::OffT) : Int32
  end
{% elsif flag?(:darwin) || flag?(:bsd) %}
  lib LibShm
    fun shm_open(name : UInt8*, oflag : Int32, mode : LibC::ModeT) : Int32
    fun shm_unlink(name : UInt8*) : Int32
    fun ftruncate(fd : Int32, length : LibC::OffT) : Int32
  end
{% else %}
  {% raise "Shared memory transmission requires a POSIX platform" %}
{% end %}

module TTY::Gfx
  ESC = '\e'

  enum Action
    Transmit
    TransmitAndDisplay
    Query
    Put
    Delete
    Frame
    AnimateControl
    Compose

    def char : Char
      case self
      in .transmit?             then 't'
      in .transmit_and_display? then 'T'
      in .query?                then 'q'
      in .put?                  then 'p'
      in .delete?               then 'd'
      in .frame?                then 'f'
      in .animate_control?      then 'a'
      in .compose?              then 'c'
      end
    end
  end

  struct Command
    alias Value = Int::Primitive | String | Char | Symbol

    @entries = [] of Tuple(Char, Value)

    def initialize
    end

    def initialize(@action : Action?)
    end

    getter action : Action?

    def action=(action : Action?) : Action?
      @action = action
    end

    def set(key : Char, value : Value) : self
      @entries << {key, value}
      self
    end

    def delete(key : Char) : self
      @entries.reject! { |(k, _)| k == key }
      self
    end

    def [](key : Char) : String?
      @entries.reverse_each do |(k, v)|
        return v.to_s if k == key
      end
      nil
    end

    def has_key?(key : Char) : Bool
      @entries.any? { |(k, _)| k == key }
    end

    def control_data : String
      String.build { |io| write_control(io) }
    end

    def write_to(io : IO, payload : String? = nil) : Nil
      open(io)
      io << payload if payload
      close(io)
    end

    def write_to(io : IO, & : IO ->) : Nil
      open(io)
      yield io
      close(io)
    end

    def to_s(payload : String? = nil) : String
      String.build { |io| write_to(io, payload) }
    end

    private def open(io : IO) : Nil
      io << ESC << "_G"
      write_control(io)
      io << ';'
    end

    private def close(io : IO) : Nil
      io << ESC << '\\'
    end

    private def write_control(io : IO) : Nil
      first = true

      if a = @action
        io << 'a' << '=' << a.char
        first = false
      end

      @entries.each do |(k, v)|
        io << ',' unless first
        io << k << '=' << v
        first = false
      end
    end
  end

  enum Format
    RGB24
    RGBA32
    PNG

    def code : Int32
      case self
      in .rgb24?  then 24
      in .rgba32? then 32
      in .png?    then 100
      end
    end

    def bytes_per_pixel : Int32?
      case self
      in .rgb24?  then 3
      in .rgba32? then 4
      in .png?    then nil
      end
    end
  end

  record Pixel, r : UInt8, g : UInt8, b : UInt8, a : UInt8 = 255_u8 do
    def self.rgb(r : Int, g : Int, b : Int) : Pixel
      new(r.to_u8, g.to_u8, b.to_u8)
    end
  end

  class Image
    getter data   : Bytes
    getter format : Format
    getter width  : Int32
    getter height : Int32

    property compressed : Bool

    def initialize(@data : Bytes, @format : Format, @width : Int32, @height : Int32, @compressed : Bool = false)
      if bpp = @format.bytes_per_pixel
        expected = @width.to_i64 * @height * bpp
        raise ArgumentError.new("data size #{@data.size} does not match #{@width}x#{@height}x#{bpp} = #{expected}") unless @data.size.to_i64 == expected
      end
    end

    def self.rgba(width : Int, height : Int, *, compressed : Bool = false, & : Int32, Int32 -> Pixel) : Image
      data   = Bytes.new(width * height * 4)
      offset = 0
      height.times do |y|
        width.times do |x|
          px = yield x, y
          data[offset] = px.r
          data[offset + 1] = px.g
          data[offset + 2] = px.b
          data[offset + 3] = px.a
          offset += 4
        end
      end
      new(data, Format::RGBA32, width, height, compressed)
    end

    def self.rgb(width : Int, height : Int, *, compressed : Bool = false, & : Int32, Int32 -> Pixel) : Image
      data   = Bytes.new(width * height * 3)
      offset = 0
      height.times do |y|
        width.times do |x|
          px = yield x, y
          data[offset] = px.r
          data[offset + 1] = px.g
          data[offset + 2] = px.b
          offset += 3
        end
      end
      new(data, Format::RGB24, width, height, compressed)
    end

    def self.from_rgba(data : Bytes, width : Int, height : Int, *, compressed : Bool = false) : Image
      new(data, Format::RGBA32, width, height, compressed)
    end

    def self.from_rgb(data : Bytes, width : Int, height : Int, *, compressed : Bool = false) : Image
      new(data, Format::RGB24, width, height, compressed)
    end

    def self.png(bytes : Bytes, *, compressed : Bool = false) : Image
      signature = Bytes[0x89_u8, 0x50_u8, 0x4E_u8, 0x47_u8, 0x0D_u8, 0x0A_u8, 0x1A_u8, 0x0A_u8]
      unless bytes.size >= 8 && bytes[0, 8] == signature
        raise ArgumentError.new("not a PNG file (bad signature)")
      end
      new(bytes, Format::PNG, 0, 0, compressed)
    end

    def self.from_png_file(path : String | Path, *, compressed : Bool = false) : Image
      png(File.read(path).to_slice, compressed: compressed)
    end

    def payload : Bytes
      return @data unless @compressed
      IO::Memory.new.tap do |io|
        Compress::Zlib::Writer.open(io) { |z| z.write(@data) }
      end.to_slice
    end
  end

  class SharedMemory
    getter name : String
    getter size : Int32

    @fd : Int32
    @closed   = false
    @unlinked = false

    def self.create(data : Bytes, *, prefix : String = "gfx") : SharedMemory
      if data.empty?
        raise ArgumentError.new("cannot create a shared memory object from empty data")
      end
      name = "/#{prefix}-#{Process.pid}-#{Random::Secure.hex(8)}"
      fd   = LibShm.shm_open(name, LibC::O_RDWR | LibC::O_CREAT | LibC::O_EXCL, 0o600)
      if fd < 0
        raise RuntimeError.from_errno("shm_open(#{name})")
      end
      shm = new(fd, name, data.size)
      begin
        shm.write(data)
        shm.close
      rescue ex
        shm.close
        LibShm.shm_unlink(name)
        raise ex
      end
      shm
    end

    def initialize(@fd : Int32, @name : String, @size : Int32)
    end

    def write(data : Bytes) : Nil
      if LibShm.ftruncate(@fd, data.size.to_i64) != 0
        raise RuntimeError.from_errno("ftruncate(#{@name})")
      end
      total = 0
      while total < data.size
        written = LibC.write(@fd, data.to_unsafe + total, (data.size - total).to_u32)
        raise RuntimeError.from_errno("write(#{@name})") if written < 0
        total += written
      end
    end

    def close : Nil
      return if @closed
      @closed = true
      LibC.close(@fd)
    end

    def unlink : Nil
      close
      return if @unlinked
      @unlinked = true
      if LibShm.shm_unlink(@name) != 0
        raise RuntimeError.from_errno("shm_unlink(#{@name})")
      end
    end

    def finalize
      close
    end
  end

  CHUNK_SIZE = 4096

  abstract class Medium
    abstract def char : Char
    abstract def send(io : IO, command : Command, payload_bytes : Bytes) : SharedMemory?
  end

  class DirectMedium < Medium
    SOURCE_CHUNK = (CHUNK_SIZE // 4) * 3

    def char : Char
      'd'
    end

    def send(io : IO, command : Command, payload_bytes : Bytes) : SharedMemory?
      command.set('t', 'd')

      offset = 0
      first  = true
      loop do
        length = Math.min(SOURCE_CHUNK, payload_bytes.size - offset)
        chunk  = payload_bytes[offset, length]
        more   = offset + length < payload_bytes.size
        cmd    = first ? command : Command.new
        cmd.set('m', more ? 1 : 0)
        if !first && command.action.try(&.frame?)
          cmd.set('a', 'f')
        end
        cmd.write_to(io) { |dest| Base64.strict_encode(chunk, dest) }
        first = false
        offset += length
        break unless more
      end
      nil
    end
  end

  abstract class NamedMedium < Medium
    def send_name(io : IO, command : Command, name : String) : Nil
      command.set('t', char)
      command.write_to(io, Base64.strict_encode(name))
    end
  end

  class FileMedium < NamedMedium
    getter path : String

    def initialize(@path : String)
    end

    def char : Char
      'f'
    end

    def send(io : IO, command : Command, payload_bytes : Bytes) : SharedMemory?
      send_name(io, command, File.expand_path(@path))
      nil
    end
  end

  class TempFileMedium < NamedMedium
    getter path : String = ""

    def char : Char
      't'
    end

    def send(io : IO, command : Command, payload_bytes : Bytes) : SharedMemory?
      @path = File.join(Dir.tempdir, "tty-graphics-protocol-#{Process.pid}-#{Random::Secure.hex(8)}.tmp")
      File.write(@path, payload_bytes)
      send_name(io, command, @path)
      nil
    end
  end

  class SharedMemoryMedium < Medium
    property prefix : String

    def initialize(@prefix : String = "gfx")
    end

    def char : Char
      's'
    end

    def send(io : IO, command : Command, payload_bytes : Bytes) : SharedMemory?
      shm = SharedMemory.create(payload_bytes, prefix: @prefix)
      begin
        command.set('t', 's')
        command.write_to(io, Base64.strict_encode(shm.name))
      rescue ex
        shm.unlink
        raise ex
      end
      shm
    end
  end

  struct Response
    getter image_id     : UInt32?
    getter image_number : UInt32?
    getter placement_id : UInt32?
    getter message      : String

    def initialize(@image_id : UInt32?, @image_number : UInt32?, @placement_id : UInt32?, @message : String)
    end

    def ok? : Bool
      @message == "OK"
    end

    def error_code : String?
      return nil if ok?
      @message.split(':', 2).first?
    end

    def to_s(io : IO) : Nil
      io << "TTY::Gfx::Response("
      io << "i=" << @image_id if @image_id
      io << ",I=" << @image_number if @image_number
      io << ",p=" << @placement_id if @placement_id
      io << ';' << @message << ')'
    end

    def self.parse(body : String) : Response?
      return nil unless body.includes?(';')
      control, _, message = body.partition(';')
      return nil if message.empty?
      i = num = p = nil
      control.split(',') do |pair|
        key, _, value = pair.partition('=')
        case key
        when "i" then i   = value.to_u32?
        when "I" then num = value.to_u32?
        when "p" then p   = value.to_u32?
        end
      end
      new(i, num, p, message)
    end

    def self.from_apc(token : TTY::Token) : Response?
      bytes = token.to_slice
      return nil unless bytes.size >= 3
      return nil unless bytes[0] == ESC.ord && bytes[1] == '_'.ord && bytes[2] == 'G'.ord

      tail = bytes.size
      if tail >= 2 && bytes[tail - 1] == '\\'.ord && bytes[tail - 2] == ESC.ord
        tail -= 2
      end

      body = String.new(bytes[3, tail - 3])
      parse(body)
    end
  end

  struct Placement
    property source_x            : Int32?
    property source_y            : Int32?
    property source_width        : Int32?
    property source_height       : Int32?
    property x_offset            : Int32?
    property y_offset            : Int32?
    property columns             : Int32?
    property rows                : Int32?
    property cursor_policy       : Int32?
    property unicode_placeholder : Bool?
    property z_index             : Int32?
    property parent_image_id     : UInt32?
    property parent_placement_id : UInt32?
    property h_offset            : Int32?
    property v_offset            : Int32?

    def initialize
    end

    def apply(command : Command) : Nil
      if v = source_x
        command.set('x', v)
      end
      if v = source_y
        command.set('y', v)
      end
      if v = source_width
        command.set('w', v)
      end
      if v = source_height
        command.set('h', v)
      end
      if v = x_offset
        command.set('X', v)
      end
      if v = y_offset
        command.set('Y', v)
      end
      if v = columns
        command.set('c', v)
      end
      if v = rows
        command.set('r', v)
      end
      if v = cursor_policy
        command.set('C', v)
      end
      command.set('U', 1) if unicode_placeholder
      if v = z_index
        command.set('z', v)
      end
      if v = parent_image_id
        command.set('P', v)
      end
      if v = parent_placement_id
        command.set('Q', v)
      end
      if v = h_offset
        command.set('H', v)
      end
      if v = v_offset
        command.set('V', v)
      end
    end
  end

  struct FrameOptions
    property x          : Int32?
    property y          : Int32?
    property base_frame : Int32?
    property edit_frame : Int32?
    property gap        : Int32?
    property replace    : Bool?
    property background : UInt32?

    def initialize
    end

    def apply(command : Command) : Nil
      if v = x
        command.set('x', v)
      end
      if v = y
        command.set('y', v)
      end
      if v = base_frame
        command.set('c', v)
      end
      if v = edit_frame
        command.set('r', v)
      end
      if v = gap
        command.set('z', v)
      end
      command.set('X', 1) if replace
      if v = background
        command.set('Y', v)
      end
    end
  end

  enum DeleteTarget
    AllVisible
    ById
    ByNumber
    AtCursor
    AnimationFrames
    AtCell
    AtCellZIndex
    IdRange
    Column
    Row
    ZIndex

    def char(free_data : Bool) : Char
      c = case self
          in .all_visible?      then 'a'
          in .by_id?            then 'i'
          in .by_number?        then 'n'
          in .at_cursor?        then 'c'
          in .animation_frames? then 'f'
          in .at_cell?          then 'p'
          in .at_cell_z_index?  then 'q'
          in .id_range?         then 'r'
          in .column?           then 'x'
          in .row?              then 'y'
          in .z_index?          then 'z'
          end
      free_data ? c.upcase : c
    end
  end

  struct TransmitOptions
    property action       : Action
    property medium       : Medium
    property id           : UInt32?
    property number       : UInt32?
    property placement_id : UInt32?
    property placement    : Placement?
    property frame        : FrameOptions?
    property quiet        : Int32
    property size         : Int32?
    property offset       : Int32?

    def initialize(@action : Action = Action::TransmitAndDisplay,
                   @medium : Medium = DirectMedium.new,
                   @id : UInt32? = nil,
                   @number : UInt32? = nil,
                   @placement_id : UInt32? = nil,
                   @placement : Placement? = nil,
                   @frame : FrameOptions? = nil,
                   @quiet : Int32 = 0,
                   @size : Int32? = nil,
                   @offset : Int32? = nil)
    end
  end

  struct PutOptions
    property id           : UInt32?
    property number       : UInt32?
    property placement_id : UInt32?
    property placement    : Placement?
    property quiet        : Int32

    def initialize(@id : UInt32? = nil,
                   @number : UInt32? = nil,
                   @placement_id : UInt32? = nil,
                   @placement : Placement? = nil,
                   @quiet : Int32 = 0)
    end
  end

  struct DeleteOptions
    property target       : DeleteTarget
    property free_data    : Bool
    property id           : UInt32?
    property number       : UInt32?
    property placement_id : UInt32?
    property x            : Int32?
    property y            : Int32?
    property z            : Int32?
    property quiet        : Int32

    def initialize(@target : DeleteTarget = DeleteTarget::AllVisible,
                   @free_data : Bool = false,
                   @id : UInt32? = nil,
                   @number : UInt32? = nil,
                   @placement_id : UInt32? = nil,
                   @x : Int32? = nil,
                   @y : Int32? = nil,
                   @z : Int32? = nil,
                   @quiet : Int32 = 0)
    end
  end

  enum AnimationState
    Stop
    RunAndWait
    Run
  end

  struct AnimateOptions
    property state         : AnimationState?
    property current_frame : Int32?
    property frame         : Int32?
    property gap           : Int32?
    property loops         : Int32?
    property quiet         : Int32

    def initialize(@state : AnimationState? = nil,
                   @current_frame : Int32? = nil,
                   @frame : Int32? = nil,
                   @gap : Int32? = nil,
                   @loops : Int32? = nil,
                   @quiet : Int32 = 0)
    end
  end

  module Encoder
    extend self

    def transmit(io : IO, image : Image, opts : TransmitOptions) : SharedMemory?
      id     = opts.id
      number = opts.number
      if id && number
        raise ArgumentError.new("specify either image id (i) or image number (I), not both")
      end
      if opts.quiet < 0 || opts.quiet > 2
        raise ArgumentError.new("quiet must be 0, 1 or 2")
      end

      cmd = Command.new(opts.action)
      cmd.set('f', image.format.code)
      cmd.set('o', 'z') if image.compressed
      cmd.set('q', opts.quiet) if opts.quiet > 0
      cmd.set('i', id) if id
      cmd.set('I', number) if number
      if pid = opts.placement_id
        cmd.set('p', pid)
      end
      if sz = opts.size
        cmd.set('S', sz)
      end
      if off = opts.offset
        cmd.set('O', off)
      end

      unless image.format.png?
        cmd.set('s', image.width)
        cmd.set('v', image.height)
      end

      if image.format.png? && image.compressed && !cmd.has_key?('S')
        cmd.set('S', image.data.size)
      end

      opts.placement.try(&.apply(cmd))
      opts.frame.try(&.apply(cmd))

      opts.medium.send(io, cmd, image.payload)
    end

    def put(io : IO, opts : PutOptions) : Nil
      id     = opts.id
      number = opts.number
      raise ArgumentError.new("put requires an image id or number") unless id || number
      if id && number
        raise ArgumentError.new("specify either image id (i) or image number (I), not both")
      end
      cmd = Command.new(Action::Put)
      cmd.set('i', id) if id
      cmd.set('I', number) if number
      if pid = opts.placement_id
        cmd.set('p', pid)
      end
      cmd.set('q', opts.quiet) if opts.quiet > 0
      opts.placement.try(&.apply(cmd))
      cmd.write_to(io)
    end

    def delete(io : IO, opts : DeleteOptions) : Nil
      id     = opts.id
      number = opts.number
      if id && number
        raise ArgumentError.new("specify either image id (i) or image number (I), not both")
      end
      cmd = Command.new(Action::Delete)
      cmd.set('d', opts.target.char(opts.free_data))
      cmd.set('i', id) if id
      cmd.set('I', number) if number
      if pid = opts.placement_id
        cmd.set('p', pid)
      end
      if x = opts.x
        cmd.set('x', x)
      end
      if y = opts.y
        cmd.set('y', y)
      end
      if z = opts.z
        cmd.set('z', z)
      end
      cmd.set('q', opts.quiet) if opts.quiet > 0
      cmd.write_to(io)
    end

    def animate(io : IO, image_id : UInt32, opts : AnimateOptions) : Nil
      cmd = Command.new(Action::AnimateControl)
      cmd.set('i', image_id)
      case opts.state
      when AnimationState::Stop       then cmd.set('s', 1)
      when AnimationState::RunAndWait then cmd.set('s', 2)
      when AnimationState::Run        then cmd.set('s', 3)
      end
      if cf = opts.current_frame
        cmd.set('c', cf)
      end
      if fr = opts.frame
        cmd.set('r', fr)
      end
      if gap = opts.gap
        cmd.set('z', gap)
      end
      if loops = opts.loops
        cmd.set('v', loops)
      end
      cmd.set('q', opts.quiet) if opts.quiet > 0
      cmd.write_to(io)
    end

    def probe(io : IO) : Nil
      probe = Command.new(Action::Query)
      probe.set('i', 31)
      probe.set('s', 1)
      probe.set('v', 1)
      probe.set('t', 'd')
      probe.set('f', 24)
      probe.write_to(io, "AAAA")
    end
  end

  struct Transmit
    include MVU::Msg
    getter image : Image
    getter opts  : TransmitOptions

    def initialize(@image : Image, @opts : TransmitOptions = TransmitOptions.new)
    end
  end

  struct Put
    include MVU::Msg
    getter opts : PutOptions

    def initialize(@opts : PutOptions = PutOptions.new)
    end
  end

  struct Delete
    include MVU::Msg
    getter opts : DeleteOptions

    def initialize(@opts : DeleteOptions = DeleteOptions.new)
    end
  end

  struct Animate
    include MVU::Msg
    getter image_id : UInt32
    getter opts     : AnimateOptions

    def initialize(@image_id : UInt32, @opts : AnimateOptions = AnimateOptions.new)
    end
  end

  struct Probe
    include MVU::Msg
  end

  struct Feed
    include MVU::Msg
    getter tokens : Array(TTY::Token)

    def initialize(@tokens : Array(TTY::Token))
    end
  end

  struct Responded
    include MVU::Msg
    getter response : Response

    def initialize(@response : Response)
    end
  end

  struct Shutdown
    include MVU::Msg
  end

  struct Model
    include MVU::Model

    getter output  : IO
    getter input   : IO?
    getter pending : Hash(UInt32, SharedMemory)
    getter last    : Response?

    def initialize(@output : IO = STDOUT, @input : IO? = STDIN, @pending : Hash(UInt32, SharedMemory) = {} of UInt32 => SharedMemory, @last : Response? = nil)
    end

    def update(msg : MVU::Msg) : {self, MVU::Cmd}
      case msg
      when Transmit
        transmit(msg.image, msg.opts)
      when Put
        write_cmd { |io| Encoder.put(io, msg.opts) }
      when Delete
        write_cmd { |io| Encoder.delete(io, msg.opts) }
      when Animate
        write_cmd { |io| Encoder.animate(io, msg.image_id, msg.opts) }
      when Probe
        write_cmd do |io|
          Encoder.probe(io)
          io << ESC << "[c"
        end
      when Feed
        feed(msg.tokens)
      when Responded
        respond(msg.response)
      when Shutdown
        drain
      else
        {self, MVU::Cmd.none}
      end
    end

    def view : String
      ""
    end

    def subscription_ids : Array(MVU::SubId)
      return MVU::Sub::NO_IDS if @input.nil?
      [:gfx_read] of MVU::SubId
    end

    def subscription(id : MVU::SubId) : MVU::Sub
      source = @input
      raise "TTY::Gfx::Model has no subscription for #{id.inspect}" unless source

      MVU::Sub.new(id) do |dispatch, cancel|
        buffer    = Bytes.new(4096)
        tokenizer = TTY::Tokenizer.new
        until cancel.closed?
          begin
            bytes_read = source.read(buffer)
            break if bytes_read == 0
            tokens = tokenizer.feed(buffer[0, bytes_read]).select(&.kind.apc?)
            dispatch.call(Feed.new(tokens)) unless tokens.empty?
          rescue IO::Error
            break
          end
        end
      end
    end

    private def transmit(image : Image, opts : TransmitOptions) : {self, MVU::Cmd}
      shm : SharedMemory? = nil

      cmd = MVU::Cmd.sync do
        shm = Encoder.transmit(@output, image, opts)
        @output.flush
        nil.as(MVU::Msg?)
      end

      pending = @pending
      if (created = shm).nil?
        return {self, cmd}
      end

      if id = opts.id
        pending = @pending.dup
        pending[id] = created
        {Model.new(@output, @input, pending, @last), cmd}
      else
        cleanup = MVU::Cmd.sync do
          created.unlink rescue nil
          nil.as(MVU::Msg?)
        end
        {self, MVU::Cmd.batch([cmd, cleanup])}
      end
    end

    private def feed(tokens : Array(TTY::Token)) : {self, MVU::Cmd}
      responses = [] of Response
      tokens.each do |token|
        if response = Response.from_apc(token)
          responses << response
        end
      end

      return {self, MVU::Cmd.none} if responses.empty?

      cmds = responses.map do |response|
        MVU::Cmd.sync { Responded.new(response).as(MVU::Msg?) }
      end

      {self, MVU::Cmd.batch(cmds)}
    end

    private def respond(response : Response) : {self, MVU::Cmd}
      id = response.image_id
      unless id && (shm = @pending[id]?)
        return {Model.new(@output, @input, @pending, response), MVU::Cmd.none}
      end

      pending = @pending.dup
      pending.delete(id)

      cmd = MVU::Cmd.sync do
        shm.unlink rescue nil
        nil.as(MVU::Msg?)
      end

      {Model.new(@output, @input, pending, response), cmd}
    end

    private def drain : {self, MVU::Cmd}
      return {self, MVU::Cmd.none} if @pending.empty?

      shms = @pending.values

      cmd = MVU::Cmd.sync do
        shms.each { |shm| shm.unlink rescue nil }
        nil.as(MVU::Msg?)
      end

      {Model.new(@output, @input, {} of UInt32 => SharedMemory, @last), cmd}
    end

    private def write_cmd(&block : IO ->) : {self, MVU::Cmd}
      cmd = MVU::Cmd.sync do
        block.call(@output)
        @output.flush
        nil.as(MVU::Msg?)
      end
      {self, cmd}
    end
  end
end
