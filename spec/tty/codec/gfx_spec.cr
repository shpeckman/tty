# spec/tty/codec/gfx_spec.cr
require "../../spec_helper"

private alias Gfx = TTY::Codec::Gfx

private def apc(sequence : Bytes) : TTY::Token
  TTY::VT::Parser.new.parse(sequence).find { |token| token.kind.apc? }.not_nil!
end

private def apc(sequence : String) : TTY::Token
  apc(sequence.to_slice)
end

private def c1_apc(body : String) : String
  io = IO::Memory.new
  io.write_byte(0x9F_u8)
  io << body
  io.write_byte(0x1B_u8)
  io.write_byte(0x5C_u8)
  String.new(io.to_slice)
end

private def extract_payload(token : TTY::Token) : Bytes
  bytes = token.bytes
  offset = if bytes.size >= 2 && bytes.unsafe_fetch(0) == 0x1b_u8 && bytes.unsafe_fetch(1) == 0x5f_u8
             2
           elsif bytes.size >= 1 && bytes.unsafe_fetch(0) == 0x9f_u8
             1
           else
             return Bytes.empty
           end

  end_idx = bytes.size
  if bytes.size >= 2 && bytes.unsafe_fetch(bytes.size - 2) == 0x1b_u8 && bytes.unsafe_fetch(bytes.size - 1) == 0x5c_u8
    end_idx -= 2
  elsif bytes.size >= 1 && bytes.unsafe_fetch(bytes.size - 1) == 0x9c_u8
    end_idx -= 1
  end

  bytes[offset, end_idx - offset]
end

private def command(sequence : String)
  Gfx.command(extract_payload(apc(sequence)))
end

private def response(sequence : String)
  Gfx.response(extract_payload(apc(sequence)))
end

private def feed(assembler : Gfx::Assembler, sequence : String)
  assembler.feed(extract_payload(apc(sequence)))
end

private def encoded(command : Gfx::Command, chunk_size : Int32 = Gfx::MAX_CHUNK) : Array(String)
  Gfx.encode(command, chunk_size).map { |chunk| String.new(chunk) }
end

describe TTY::Codec::Gfx do
  describe "capacity" do
    it "fits a full chunk within the default parser buffer" do
      Gfx::MIN_CAPACITY.should be <= TTY::VT::Parser::DEFAULT_CAPACITY
    end

    it "decodes a full sized chunk without truncation" do
      payload = "A" * Gfx::MAX_CHUNK
      token   = apc("\e_Gm=1;#{payload}\e\\")
      token.malformed?.should be_false
      Gfx.command(extract_payload(token)).should be_a(Gfx::Chunk)
    end
  end

  describe "rejection" do
    it "ignores sequences that do not start with G" do
      command("\e_payload\e\\").should be_nil
    end

    it "accepts the c1 introducer" do
      transmit = command(c1_apc("Ga=t,i=5;AQID")).as(Gfx::Transmit)
      transmit.id.image_id.should eq(5)
      transmit.source.data.should eq(Bytes[1, 2, 3])
    end
  end

  describe "transmission" do
    it "decodes transmit and display" do
      transmit = command("\e_Ga=T,f=100,i=31;AQID\e\\").as(Gfx::Transmit)
      transmit.id.image_id.should eq(31)
      transmit.source.format.should eq(Gfx::Format::PNG)
      transmit.source.medium.should eq(Gfx::Medium::Direct)
      transmit.source.data.should eq(Bytes[1, 2, 3])
      transmit.placement.should_not be_nil
    end

    it "decodes transmit without a placement" do
      transmit = command("\e_Ga=t,f=100,i=31;AQID\e\\").as(Gfx::Transmit)
      transmit.placement.should be_nil
    end

    it "defaults the action to transmit" do
      transmit = command("\e_Gf=24,s=2,v=1;AQIDBAUG\e\\").as(Gfx::Transmit)
      transmit.source.format.should eq(Gfx::Format::RGB)
      transmit.source.width.should eq(2)
      transmit.source.height.should eq(1)
      transmit.source.data.should eq(Bytes[1, 2, 3, 4, 5, 6])
    end

    it "reads a path for non-direct media" do
      transmit = command("\e_Ga=T,f=100,t=f;L3RtcC9hLnBuZw==\e\\").as(Gfx::Transmit)
      transmit.source.medium.should eq(Gfx::Medium::File)
      transmit.source.path.should eq("/tmp/a.png")
      transmit.source.data.should be_nil
    end

    it "leaves a path untouched when the file itself is compressed" do
      transmit = command("\e_Ga=t,t=s,o=z,f=100;L3RtcC9hLnBuZw==\e\\").as(Gfx::Transmit)
      transmit.source.compression.should eq(Gfx::Compression::Deflate)
      transmit.source.path.should eq("/tmp/a.png")
    end

    it "decodes a query" do
      query = command("\e_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\e\\").as(Gfx::Query)
      query.id.image_id.should eq(31)
      query.source.width.should eq(1)
      query.source.format.should eq(Gfx::Format::RGB)
    end

    it "carries the quiet level" do
      transmit = command("\e_Ga=t,q=2,f=100;AQID\e\\").as(Gfx::Transmit)
      transmit.quiet.should eq(Gfx::Quiet::Silent)
    end

    it "ignores unknown keys" do
      transmit = command("\e_Ga=t,i=1,k=5,f=100;AQID\e\\").as(Gfx::Transmit)
      transmit.id.image_id.should eq(1)
    end
  end

  describe "placement" do
    it "decodes a put" do
      put = command("\e_Ga=p,i=10,c=20,r=10,C=1,z=-1\e\\").as(Gfx::Put)
      put.id.image_id.should eq(10)
      put.placement.columns.should eq(20)
      put.placement.rows.should eq(10)
      put.placement.move_cursor?.should be_false
      put.placement.z.should eq(-1)
    end

    it "decodes a virtual placement" do
      put = command("\e_Ga=p,U=1,i=42,c=2,r=2\e\\").as(Gfx::Put)
      put.placement.virtual?.should be_true
    end

    it "decodes a relative placement" do
      put = command("\e_Ga=p,i=2,p=3,P=1,Q=4,H=-2,V=5\e\\").as(Gfx::Put)
      put.id.placement_id.should eq(3)
      put.placement.parent.should eq(1)
      put.placement.parent_placement.should eq(4)
      put.placement.offset_x.should eq(-2)
      put.placement.offset_y.should eq(5)
    end
  end

  describe "delete" do
    it "defaults to deleting all visible placements" do
      delete = command("\e_Ga=d\e\\").as(Gfx::Delete)
      delete.target.should eq(Gfx::DeleteTarget::All)
      delete.free_data?.should be_false
    end

    it "reads the selector case as the free data flag" do
      delete = command("\e_Ga=d,d=I,i=10,p=7\e\\").as(Gfx::Delete)
      delete.target.should eq(Gfx::DeleteTarget::Id)
      delete.free_data?.should be_true
      delete.id.image_id.should eq(10)
      delete.id.placement_id.should eq(7)
    end

    it "decodes a z-index delete" do
      delete = command("\e_Ga=d,d=Z,z=-1\e\\").as(Gfx::Delete)
      delete.target.should eq(Gfx::DeleteTarget::ZIndex)
      delete.z.should eq(-1)
    end

    it "decodes a cell delete" do
      delete = command("\e_Ga=d,d=p,x=3,y=4\e\\").as(Gfx::Delete)
      delete.target.should eq(Gfx::DeleteTarget::Cell)
      delete.free_data?.should be_false
      delete.x.should eq(3)
      delete.y.should eq(4)
    end

    it "rejects an unknown selector" do
      failure = command("\e_Ga=d,d=w\e\\").as(Gfx::Failure)
      failure.code.should eq(Gfx::ErrorCode::EINVAL)
    end
  end

  describe "animation" do
    it "decodes frame data" do
      frame = command("\e_Ga=f,i=1,s=2,v=2,c=1,r=2,z=100,X=1,Y=4278190335;AQID\e\\").as(Gfx::FrameTransmit)
      frame.id.image_id.should eq(1)
      frame.source.width.should eq(2)
      frame.frame.base.should eq(1)
      frame.frame.edit.should eq(2)
      frame.frame.gap.should eq(100)
      frame.frame.blend.should eq(Gfx::Blend::Replace)
      frame.frame.background.should eq(4278190335_u32)
    end

    it "decodes a gapless frame" do
      frame = command("\e_Ga=f,i=1,r=2,z=-1;AQID\e\\").as(Gfx::FrameTransmit)
      frame.frame.gap.should eq(-1)
    end

    it "decodes a current frame change" do
      animate = command("\e_Ga=a,i=3,c=7\e\\").as(Gfx::Animate)
      animate.current.should eq(7)
      animate.state.should eq(Gfx::AnimState::Unspecified)
    end

    it "decodes a gap change" do
      animate = command("\e_Ga=a,i=7,r=3,z=48\e\\").as(Gfx::Animate)
      animate.frame.should eq(3)
      animate.gap.should eq(48)
    end

    it "decodes playback control" do
      animate = command("\e_Ga=a,i=7,s=3,v=4\e\\").as(Gfx::Animate)
      animate.state.should eq(Gfx::AnimState::Run)
      animate.loops.should eq(4)
    end

    it "rejects an unknown animation state" do
      failure = command("\e_Ga=a,i=7,s=9\e\\").as(Gfx::Failure)
      failure.code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "decodes a composition with r as source and c as destination" do
      compose = command("\e_Ga=c,i=1,r=7,c=9,w=23,h=27,X=4,Y=8,x=1,y=3\e\\").as(Gfx::Compose)
      compose.id.image_id.should eq(1)
      compose.source_frame.should eq(7)
      compose.target_frame.should eq(9)
      compose.source.x.should eq(4)
      compose.source.y.should eq(8)
      compose.target.x.should eq(1)
      compose.target.y.should eq(3)
      compose.source.width.should eq(23)
      compose.source.height.should eq(27)
      compose.blend.should eq(Gfx::Blend::Alpha)
    end

    it "decodes a replacing composition" do
      compose = command("\e_Ga=c,i=1,r=1,c=2,C=1\e\\").as(Gfx::Compose)
      compose.blend.should eq(Gfx::Blend::Replace)
    end
  end

  describe "failures" do
    it "rejects i and I together" do
      failure = command("\e_Ga=T,i=1,I=2;AQID\e\\").as(Gfx::Failure)
      failure.code.should eq(Gfx::ErrorCode::EINVAL)
      failure.id.image_id.should eq(1)
      failure.id.image_number.should eq(2)
    end

    it "rejects an unknown action" do
      command("\e_Ga=Z;AQID\e\\").as(Gfx::Failure).code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "rejects an unsupported format" do
      command("\e_Ga=t,f=48;AQID\e\\").as(Gfx::Failure).code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "rejects an unsupported medium" do
      command("\e_Ga=t,t=x;AQID\e\\").as(Gfx::Failure).code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "rejects malformed control data" do
      command("\e_Ga=T,f\e\\").as(Gfx::Failure).code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "rejects an invalid payload" do
      command("\e_Ga=t,f=100;!!!!\e\\").as(Gfx::Failure).code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "rejects a corrupt deflate stream" do
      command("\e_Ga=t,f=100,o=z;AQIDBAUG\e\\").as(Gfx::Failure).code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "carries the quiet level into the response" do
      failure = command("\e_Ga=Z,q=1;AQID\e\\").as(Gfx::Failure)
      failure.quiet.should eq(Gfx::Quiet::NoOk)
      failure.response.ok?.should be_false
    end
  end

  describe "chunks" do
    it "decodes a bare continuation" do
      chunk = command("\e_Gm=1;AQID\e\\").as(Gfx::Chunk)
      chunk.more?.should be_true
      chunk.frame?.should be_false
      chunk.decode.should eq(Bytes[1, 2, 3])
    end

    it "decodes a final continuation" do
      chunk = command("\e_Gm=0;BAUG\e\\").as(Gfx::Chunk)
      chunk.more?.should be_false
      chunk.decode.should eq(Bytes[4, 5, 6])
    end

    it "decodes a frame continuation" do
      chunk = command("\e_Ga=f,m=0;AQID\e\\").as(Gfx::Chunk)
      chunk.frame?.should be_true
    end

    it "treats a keyed first chunk as a command" do
      transmit = command("\e_Ga=T,f=100,i=1,m=1;AQID\e\\").as(Gfx::Transmit)
      transmit.source.more?.should be_true
    end

    it "does not inflate an incomplete payload" do
      transmit = command("\e_Ga=t,f=100,o=z,m=1;AQIDBAUG\e\\").as(Gfx::Transmit)
      transmit.source.data.should eq(Bytes[1, 2, 3, 4, 5, 6])
    end
  end

  describe "responses" do
    it "decodes an ok reply" do
      reply = response("\e_Gi=31;OK\e\\").not_nil!
      reply.ok?.should be_true
      reply.id.image_id.should eq(31)
    end

    it "decodes an image number reply" do
      reply = response("\e_Gi=99,I=13;OK\e\\").not_nil!
      reply.id.image_id.should eq(99)
      reply.id.image_number.should eq(13)
    end

    it "decodes an error reply" do
      reply = response("\e_Gi=10;ENOENT:not found\e\\").not_nil!
      reply.ok?.should be_false
      reply.code.should eq(Gfx::ErrorCode::ENOENT)
      reply.message.should eq("not found")
    end

    it "decodes a bare error code" do
      response("\e_Gi=10;EINVAL\e\\").not_nil!.code.should eq(Gfx::ErrorCode::EINVAL)
    end

    it "does not read a command as a reply" do
      response("\e_Ga=T,f=100;AQID\e\\").should be_nil
    end

    it "does not read an unknown code as a reply" do
      response("\e_Gi=10;EWHAT:nope\e\\").should be_nil
    end

    it "encodes an ok reply" do
      String.new(Gfx::Response.ok(Gfx::Id.image(7)).to_slice).should eq("\e_Gi=7;OK\e\\")
    end

    it "encodes an error reply" do
      reply = Gfx::Response.new(Gfx::Id.image(7, 3), Gfx::ErrorCode::ENOENT, "missing")
      String.new(reply.to_slice).should eq("\e_Gi=7,p=3;ENOENT:missing\e\\")
    end

    it "suppresses replies per the quiet level" do
      ok  = Gfx::Response.ok(Gfx::Id.image(1))
      bad = Gfx::Response.new(Gfx::Id.image(1), Gfx::ErrorCode::EINVAL)

      ok.suppressed?(Gfx::Quiet::All).should be_false
      ok.suppressed?(Gfx::Quiet::NoOk).should be_true
      bad.suppressed?(Gfx::Quiet::NoOk).should be_false
      bad.suppressed?(Gfx::Quiet::Silent).should be_true
    end
  end

  describe "encoding" do
    it "encodes a transmit and display" do
      transmit = Gfx::Transmit.new(Gfx::Id.image(31), Gfx::Source.png(Bytes[1, 2, 3]), Gfx::Placement.new)
      encoded(transmit).should eq(["\e_Ga=T,i=31,f=100;AQID\e\\"])
    end

    it "encodes a transmit without a placement" do
      transmit = Gfx::Transmit.new(Gfx::Id.image(31), Gfx::Source.png(Bytes[1, 2, 3]))
      encoded(transmit).should eq(["\e_Ga=t,i=31,f=100;AQID\e\\"])
    end

    it "omits defaulted keys" do
      transmit = Gfx::Transmit.new(source: Gfx::Source.rgb(Bytes[1, 2, 3, 4, 5, 6], 2, 1))
      encoded(transmit).should eq(["\e_Ga=t,f=24,s=2,v=1;AQIDBAUG\e\\"])
    end

    it "encodes a put" do
      put = Gfx::Put.new(Gfx::Id.image(10), Gfx::Placement.new(columns: 20, rows: 10, move_cursor: false))
      encoded(put).should eq(["\e_Ga=p,i=10,c=20,r=10,C=1\e\\"])
    end

    it "encodes a delete without a payload" do
      delete = Gfx::Delete.new(Gfx::Id.image(10, 7), Gfx::DeleteTarget::Id, true)
      encoded(delete).should eq(["\e_Ga=d,d=I,i=10,p=7\e\\"])
    end

    it "encodes the quiet level" do
      put = Gfx::Put.new(Gfx::Id.image(1), Gfx::Placement.new, Gfx::Quiet::Silent)
      encoded(put).should eq(["\e_Ga=p,i=1,q=2\e\\"])
    end

    it "encodes a composition" do
      compose = Gfx::Compose.new(
        Gfx::Id.image(1),
        7,
        9,
        Gfx::Rect.new(4, 8, 23, 27),
        Gfx::Rect.new(1, 3, 23, 27)
      )
      encoded(compose).should eq(["\e_Ga=c,i=1,c=9,r=7,x=1,y=3,w=23,h=27,X=4,Y=8\e\\"])
    end

    it "chunks a payload that exceeds the chunk size" do
      transmit = Gfx::Transmit.new(source: Gfx::Source.rgb(Bytes[1, 2, 3, 4, 5, 6], 2, 1))
      encoded(transmit, 4).should eq([
        "\e_Ga=t,f=24,s=2,v=1,m=1;AQID\e\\",
        "\e_Gm=0;BAUG\e\\",
      ])
    end

    it "keeps the frame action on continuations" do
      frame  = Gfx::FrameTransmit.new(Gfx::Id.image(1), Gfx::Source.rgb(Bytes[1, 2, 3, 4, 5, 6], 2, 1))
      chunks = encoded(frame, 4)
      chunks.size.should eq(2)
      chunks[1].should eq("\e_Ga=f,m=0;BAUG\e\\")
    end
  end

  describe "round trip" do
    it "survives a transmit" do
      transmit = Gfx::Transmit.new(
        Gfx::Id.image(31, 4),
        Gfx::Source.rgba(Bytes[9, 8, 7, 6], 1, 1),
        Gfx::Placement.new(columns: 4, rows: 2, z: -3, virtual: true)
      )

      decoded = Gfx.command(extract_payload(apc(Gfx.encode(transmit)[0]))).as(Gfx::Transmit)
      decoded.id.image_id.should eq(31)
      decoded.id.placement_id.should eq(4)
      decoded.source.data.should eq(Bytes[9, 8, 7, 6])
      decoded.placement.not_nil!.z.should eq(-3)
      decoded.placement.not_nil!.virtual?.should be_true
    end

    it "survives a compressed transmit" do
      data = Bytes.new(256) { |index| (index % 251).to_u8 }
      transmit = Gfx::Transmit.new(
        Gfx::Id.image(1),
        Gfx::Source.png(data, Gfx::Compression::Deflate)
      )

      chunks = Gfx.encode(transmit, Gfx::MAX_CHUNK)
      chunks.size.should eq(1)
      Gfx.command(extract_payload(apc(chunks[0]))).as(Gfx::Transmit).source.data.should eq(data)
    end

    it "survives a delete" do
      delete  = Gfx::Delete.new(Gfx::Id.image(3), Gfx::DeleteTarget::CellZ, true, 5, 6, -7)
      decoded = Gfx.command(extract_payload(apc(Gfx.encode(delete)[0]))).as(Gfx::Delete)
      decoded.target.should eq(Gfx::DeleteTarget::CellZ)
      decoded.free_data?.should be_true
      decoded.x.should eq(5)
      decoded.y.should eq(6)
      decoded.z.should eq(-7)
    end

    it "survives an animation control" do
      animate = Gfx::Animate.new(Gfx::Id.image(2), Gfx::AnimState::LoadWait, 3, -1, 4, 5)
      decoded = Gfx.command(extract_payload(apc(Gfx.encode(animate)[0]))).as(Gfx::Animate)
      decoded.state.should eq(Gfx::AnimState::LoadWait)
      decoded.frame.should eq(3)
      decoded.gap.should eq(-1)
      decoded.current.should eq(4)
      decoded.loops.should eq(5)
    end

    it "survives a composition" do
      compose = Gfx::Compose.new(
        Gfx::Id.image(1),
        7,
        9,
        Gfx::Rect.new(4, 8, 23, 27),
        Gfx::Rect.new(1, 3, 23, 27),
        Gfx::Blend::Replace
      )

      decoded = Gfx.command(extract_payload(apc(Gfx.encode(compose)[0]))).as(Gfx::Compose)
      decoded.source_frame.should eq(7)
      decoded.target_frame.should eq(9)
      decoded.source.x.should eq(4)
      decoded.target.x.should eq(1)
      decoded.blend.should eq(Gfx::Blend::Replace)
    end
  end

  describe "assembler" do
    it "holds until the final chunk arrives" do
      assembler = Gfx::Assembler.new

      feed(assembler, "\e_Ga=T,f=100,i=1,m=1;AQID\e\\").should be_nil
      assembler.pending?.should be_true

      transmit = feed(assembler, "\e_Gm=0;BAUG\e\\").as(Gfx::Transmit)
      transmit.id.image_id.should eq(1)
      transmit.source.data.should eq(Bytes[1, 2, 3, 4, 5, 6])
      transmit.source.more?.should be_false
      assembler.pending?.should be_false
    end

    it "returns an unchunked command immediately" do
      assembler = Gfx::Assembler.new
      feed(assembler, "\e_Ga=T,f=100,i=1;AQID\e\\").should be_a(Gfx::Transmit)
      assembler.pending?.should be_false
    end

    it "ignores a continuation with nothing pending" do
      feed(Gfx::Assembler.new, "\e_Gm=0;AQID\e\\").should be_nil
    end

    it "aborts a partial upload on delete" do
      assembler = Gfx::Assembler.new
      feed(assembler, "\e_Ga=T,f=100,i=1,m=1;AQID\e\\").should be_nil
      feed(assembler, "\e_Ga=d\e\\").should be_a(Gfx::Delete)
      assembler.pending?.should be_false
      feed(assembler, "\e_Gm=0;BAUG\e\\").should be_nil
    end

    it "aborts a partial upload on an unrelated command" do
      assembler = Gfx::Assembler.new
      feed(assembler, "\e_Ga=T,f=100,i=1,m=1;AQID\e\\").should be_nil
      feed(assembler, "\e_Ga=p,i=2\e\\").should be_a(Gfx::Put)
      assembler.pending?.should be_false
    end

    it "reports a quota overrun" do
      assembler = Gfx::Assembler.new(max_payload: 2)
      failure   = feed(assembler, "\e_Ga=T,f=100,i=1,m=1;AQID\e\\").as(Gfx::Failure)
      failure.code.should eq(Gfx::ErrorCode::ENOSPC)
      assembler.pending?.should be_false
    end

    it "rejects a corrupt continuation" do
      assembler = Gfx::Assembler.new
      feed(assembler, "\e_Ga=T,f=100,i=1,m=1;AQID\e\\").should be_nil
      failure = feed(assembler, "\e_Gm=0;!!!!\e\\").as(Gfx::Failure)
      failure.code.should eq(Gfx::ErrorCode::EINVAL)
      assembler.pending?.should be_false
    end

    it "reassembles a chunked transmit" do
      data     = Bytes.new(1024) { |index| (index % 251).to_u8 }
      transmit = Gfx::Transmit.new(Gfx::Id.image(9), Gfx::Source.png(data), Gfx::Placement.new(columns: 8))

      assembler = Gfx::Assembler.new
      results   = [] of Gfx::Command | Gfx::Failure

      Gfx.encode(transmit, 64) do |chunk|
        outcome = assembler.feed(extract_payload(apc(chunk)))
        results << outcome if outcome
      end

      results.size.should eq(1)
      decoded = results[0].as(Gfx::Transmit)
      decoded.id.image_id.should eq(9)
      decoded.source.data.should eq(data)
      decoded.placement.not_nil!.columns.should eq(8)
    end

    it "reassembles a chunked compressed transmit" do
      data     = Bytes.new(1024) { |index| (index % 17).to_u8 }
      transmit = Gfx::Transmit.new(Gfx::Id.image(9), Gfx::Source.png(data, Gfx::Compression::Deflate))

      assembler = Gfx::Assembler.new
      results   = [] of Gfx::Command | Gfx::Failure

      Gfx.encode(transmit, 32) do |chunk|
        outcome = assembler.feed(extract_payload(apc(chunk)))
        results << outcome if outcome
      end

      results.size.should eq(1)
      results[0].as(Gfx::Transmit).source.data.should eq(data)
    end

    it "reassembles chunked frame data" do
      data = Bytes.new(512) { |index| (index % 97).to_u8 }
      frame = Gfx::FrameTransmit.new(
        Gfx::Id.image(4),
        Gfx::Source.png(data),
        Gfx::Frame.new(base: 1, edit: 2, gap: 60)
      )

      assembler = Gfx::Assembler.new
      results   = [] of Gfx::Command | Gfx::Failure

      Gfx.encode(frame, 40) do |chunk|
        outcome = assembler.feed(extract_payload(apc(chunk)))
        results << outcome if outcome
      end

      results.size.should eq(1)
      decoded = results[0].as(Gfx::FrameTransmit)
      decoded.source.data.should eq(data)
      decoded.frame.gap.should eq(60)
    end
  end
end
