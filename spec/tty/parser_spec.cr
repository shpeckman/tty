# spec/tty/parser_spec.cr
require "../spec_helper"

private def kinds(tokens)
  tokens.map(&.kind)
end

private def bytes(tokens)
  io = IO::Memory.new
  tokens.each { |token| io.write(token.bytes) }
  io.to_slice
end

private def text(tokens)
  String.new(bytes(tokens.select(&.text?)))
end

describe TTY::VT::Parser do
  describe "text" do
    it "emits ground text as a run of single-codepoint tokens" do
      tokens = TTY::VT::Parser.new.parse("hi")
      kinds(tokens).should eq([TTY::Token::Kind::Text, TTY::Token::Kind::Text])
      text(tokens).should eq("hi")
      tokens.each { |token| token.malformed?.should be_false }
    end

    it "splits C0 controls out of text" do
      tokens = TTY::VT::Parser.new.parse("ab\ncd")
      kinds(tokens).should eq([
        TTY::Token::Kind::Text,
        TTY::Token::Kind::Text,
        TTY::Token::Kind::C0,
        TTY::Token::Kind::Text,
        TTY::Token::Kind::Text,
      ])
      tokens[2].bytes.should eq(Bytes[0x0A])
      text(tokens).should eq("abcd")
    end
  end

  describe "utf-8 boundary handling" do
    it "assembles a two-byte codepoint split across parse calls" do
      parser = TTY::VT::Parser.new
      first  = parser.parse(Bytes[0x61, 0xC2])
      second = parser.parse(Bytes[0xA5, 0x62])

      text(first).should eq("a")
      first.size.should eq(1)

      kinds(second).should eq([TTY::Token::Kind::Text, TTY::Token::Kind::Text])
      String.new(second[0].bytes).should eq("¥")
      second[0].malformed?.should be_false
      String.new(second[1].bytes).should eq("b")
    end

    it "assembles a three-byte codepoint fed one byte at a time" do
      parser = TTY::VT::Parser.new
      parser.parse(Bytes[0xE2]).should be_empty
      parser.parse(Bytes[0x82]).should be_empty
      tokens = parser.parse(Bytes[0xAC])

      tokens.size.should eq(1)
      String.new(tokens[0].bytes).should eq("€")
      tokens[0].malformed?.should be_false
    end

    it "assembles a four-byte codepoint split across calls" do
      parser = TTY::VT::Parser.new
      parser.parse(Bytes[0xF0, 0x9F]).should be_empty
      tokens = parser.parse(Bytes[0x98, 0x80])

      tokens.size.should eq(1)
      String.new(tokens[0].bytes).should eq("😀")
    end

    it "emits a complete trailing codepoint without holding it" do
      tokens = TTY::VT::Parser.new.parse("¥")
      tokens.size.should eq(1)
      String.new(tokens[0].bytes).should eq("¥")
    end

    it "resolves a held lead terminated by a non-continuation byte as malformed" do
      parser = TTY::VT::Parser.new
      parser.parse(Bytes[0xE2]).should be_empty
      tokens = parser.parse(Bytes[0x41])

      kinds(tokens).should eq([TTY::Token::Kind::Text, TTY::Token::Kind::Text])
      tokens[0].malformed?.should be_true
      tokens[0].bytes.should eq(Bytes[0xE2])
      tokens[1].malformed?.should be_false
      tokens[1].bytes.should eq(Bytes[0x41])
    end

    it "marks a stray continuation byte with no lead as malformed" do
      tokens = TTY::VT::Parser.new.parse(Bytes[0xA5])
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::Text)
      tokens[0].malformed?.should be_true
      tokens[0].bytes.should eq(Bytes[0xA5])
    end

    it "flushes a held partial codepoint as malformed text" do
      parser = TTY::VT::Parser.new
      parser.parse(Bytes[0xF0, 0x9F]).should be_empty
      flushed = parser.flush

      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::Text)
      flushed[0].malformed?.should be_true
      flushed[0].bytes.should eq(Bytes[0xF0, 0x9F])
    end

    it "flushes a held codepoint before a following control" do
      parser = TTY::VT::Parser.new
      tokens = parser.parse(Bytes[0xE2, 0x0A])

      kinds(tokens).should eq([TTY::Token::Kind::Text, TTY::Token::Kind::C0])
      tokens[0].malformed?.should be_true
      tokens[0].bytes.should eq(Bytes[0xE2])
      tokens[1].bytes.should eq(Bytes[0x0A])
    end
  end

  describe "escape sequences" do
    it "tokenizes a CSI sequence" do
      tokens = TTY::VT::Parser.new.parse("\e[1;2m")
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::CSI)
      String.new(tokens[0].bytes).should eq("\e[1;2m")
    end

    it "tokenizes a CSI split across parse calls" do
      parser = TTY::VT::Parser.new
      parser.parse("\e[1").should be_empty
      tokens = parser.parse(";2m")
      tokens.size.should eq(1)
      String.new(tokens[0].bytes).should eq("\e[1;2m")
    end

    it "emits SS2 and SS3 from their two-byte ESC forms" do
      kinds(TTY::VT::Parser.new.parse("\eN")).should eq([TTY::Token::Kind::SS2])
      kinds(TTY::VT::Parser.new.parse("\eO")).should eq([TTY::Token::Kind::SS3])
    end

    it "emits a bare two-byte ESC sequence" do
      tokens = TTY::VT::Parser.new.parse("\eM")
      tokens[0].kind.should eq(TTY::Token::Kind::ESC)
      String.new(tokens[0].bytes).should eq("\eM")
    end
  end

  describe "c1 controls" do
    it "emits SS2 and SS3 from single-byte C1 bytes" do
      kinds(TTY::VT::Parser.new.parse(Bytes[0x8E])).should eq([TTY::Token::Kind::SS2])
      kinds(TTY::VT::Parser.new.parse(Bytes[0x8F])).should eq([TTY::Token::Kind::SS3])
    end

    it "enters a CSI from the C1 introducer" do
      tokens = TTY::VT::Parser.new.parse(Bytes[0x9B, 0x31, 0x6D])
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::CSI)
    end
  end

  describe "string sequences" do
    it "terminates an OSC on BEL" do
      tokens = TTY::VT::Parser.new.parse("\e]0;title\a")
      tokens[0].kind.should eq(TTY::Token::Kind::OSC)
      String.new(tokens[0].bytes).should eq("\e]0;title")
    end

    it "terminates a DCS on ST" do
      tokens = TTY::VT::Parser.new.parse("\ePq#0\e\\")
      tokens[0].kind.should eq(TTY::Token::Kind::DCS)
      String.new(tokens[0].bytes).should eq("\ePq#0")
    end

    it "terminates an APC on ST" do
      tokens = TTY::VT::Parser.new.parse("\e_payload\e\\")
      tokens[0].kind.should eq(TTY::Token::Kind::APC)
      String.new(tokens[0].bytes).should eq("\e_payload")
    end

    it "terminates a PM on ST" do
      tokens = TTY::VT::Parser.new.parse("\e^data\e\\")
      tokens[0].kind.should eq(TTY::Token::Kind::PM)
    end

    it "emits an OSC split across parse calls" do
      parser = TTY::VT::Parser.new
      parser.parse("\e]0;ti").should be_empty
      tokens = parser.parse("tle\a")
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::OSC)
      String.new(tokens[0].bytes).should eq("\e]0;title")
    end
  end

  describe "flush" do
    it "flushes an incomplete CSI as malformed under its kind" do
      parser = TTY::VT::Parser.new
      parser.parse("\e[1;2").should be_empty
      flushed = parser.flush
      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::CSI)
      flushed[0].malformed?.should be_true
      String.new(flushed[0].bytes).should eq("\e[1;2")
    end

    it "flushes an unterminated OSC as malformed under its kind" do
      parser = TTY::VT::Parser.new
      parser.parse("\e]0;partial").should be_empty
      flushed = parser.flush
      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::OSC)
      flushed[0].malformed?.should be_true
    end

    it "flushes a lone trailing ESC as a malformed ESC token" do
      parser = TTY::VT::Parser.new
      parser.parse("\e").should be_empty
      flushed = parser.flush
      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::ESC)
      flushed[0].malformed?.should be_true
    end

    it "flushes cleanly when nothing is held" do
      TTY::VT::Parser.new.flush.should be_empty
    end
  end

  describe "string cap" do
    it "truncates an overlong OSC and marks it truncated" do
      parser = TTY::VT::Parser.new(capacity: 8)
      tokens = parser.parse(("\e]0;" + "x" * 64 + "\a"))

      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::OSC)
      tokens[0].malformed?.should be_true
      tokens[0].bytes.size.should eq(8)
    end

    it "recovers ground text after a truncated string terminates" do
      parser = TTY::VT::Parser.new(capacity: 8)
      parser.parse(("\e]0;" + "x" * 64 + "\a"))
      following = parser.parse("hi")
      text(following).should eq("hi")
    end

    it "truncates an overlong CSI" do
      parser = TTY::VT::Parser.new(capacity: 4)
      tokens = parser.parse(("\e[" + "1;" * 32 + "m"))
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::CSI)
      tokens[0].malformed?.should be_true
      tokens[0].bytes.size.should eq(4)
    end
  end

  describe "reset" do
    it "clears held codepoint and sequence state" do
      parser = TTY::VT::Parser.new
      parser.parse(Bytes[0xF0, 0x9F])
      parser.parse("\e[1")
      parser.reset
      parser.flush.should be_empty

      tokens = parser.parse("ok")
      text(tokens).should eq("ok")
    end
  end

  describe "ownership" do
    it "returns tokens that own their bytes past the next parse" do
      parser = TTY::VT::Parser.new
      first  = parser.parse(Bytes[0xC2, 0xA5])
      String.new(first[0].bytes).should eq("¥")

      parser.parse("zzzz")
      String.new(first[0].bytes).should eq("¥")
    end

    it "yields single-codepoint tokens to the block form" do
      collected = [] of TTY::Token::Kind
      TTY::VT::Parser.new.parse("a\nb") { |token| collected << token.kind }
      collected.should eq([
        TTY::Token::Kind::Text,
        TTY::Token::Kind::C0,
        TTY::Token::Kind::Text,
      ])
    end
  end
end
