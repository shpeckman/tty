# spec/tty/tokenizer_spec.cr
require "../spec_helper"

private def kinds(tokens)
  tokens.map(&.kind)
end

private def text(tokens)
  String.new(tokens.select(&.text?).flat_map(&.bytes.to_a).to_unsafe.to_slice(tokens.select(&.text?).sum(&.bytes.size)))
end

describe TTY::Tokenizer do
  describe "text" do
    it "emits a single text token for a plain run" do
      tokens = TTY::Tokenizer.new.feed("hello".to_slice)
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::Text)
      String.new(tokens[0].bytes).should eq("hello")
      tokens[0].malformed?.should be_false
    end

    it "splits control bytes out of text" do
      tokens = TTY::Tokenizer.new.feed("ab\ncd".to_slice)
      kinds(tokens).should eq([
        TTY::Token::Kind::Text,
        TTY::Token::Kind::C0,
        TTY::Token::Kind::Text,
      ])
      tokens[1].bytes.should eq(Bytes[0x0A])
    end
  end

  describe "utf-8 boundary handling" do
    it "holds a split two-byte sequence across feeds" do
      tk     = TTY::Tokenizer.new
      first  = tk.feed(Bytes[0x61, 0xC2])
      second = tk.feed(Bytes[0xA5, 0x62])

      first.size.should eq(1)
      String.new(first[0].bytes).should eq("a")

      second.size.should eq(2)
      String.new(second[0].bytes).should eq("¥")
      second[0].malformed?.should be_false
      String.new(second[1].bytes).should eq("b")
    end

    it "holds a split three-byte sequence one byte at a time" do
      tk = TTY::Tokenizer.new
      tk.feed(Bytes[0xE2]).should be_empty
      tk.feed(Bytes[0x82]).should be_empty
      tokens = tk.feed(Bytes[0xAC])

      tokens.size.should eq(1)
      String.new(tokens[0].bytes).should eq("€")
    end

    it "holds a split four-byte sequence" do
      tk = TTY::Tokenizer.new
      tk.feed(Bytes[0xF0, 0x9F]).should be_empty
      tokens = tk.feed(Bytes[0x98, 0x80])

      String.new(tokens[0].bytes).should eq("😀")
    end

    it "does not hold a complete trailing sequence" do
      tokens = TTY::Tokenizer.new.feed("¥".to_slice)
      tokens.size.should eq(1)
      String.new(tokens[0].bytes).should eq("¥")
    end

    it "resolves a held sequence terminated by a non-continuation byte as malformed" do
      tk = TTY::Tokenizer.new
      tk.feed(Bytes[0xE2]).should be_empty
      tokens = tk.feed(Bytes[0x41])

      tokens[0].kind.should eq(TTY::Token::Kind::Text)
      tokens[0].malformed?.should be_true
      tokens[0].bytes.should eq(Bytes[0xE2])
      tokens[1].bytes.should eq(Bytes[0x41])
    end

    it "flushes a held partial sequence as malformed text" do
      tk = TTY::Tokenizer.new
      tk.feed(Bytes[0xF0, 0x9F]).should be_empty
      flushed = tk.flush

      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::Text)
      flushed[0].malformed?.should be_true
      flushed[0].bytes.should eq(Bytes[0xF0, 0x9F])
    end
  end

  describe "escape sequences" do
    it "tokenizes a CSI sequence" do
      tokens = TTY::Tokenizer.new.feed("\e[1;2m".to_slice)
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::CSI)
      String.new(tokens[0].bytes).should eq("\e[1;2m")
    end

    it "tokenizes a CSI split across feeds" do
      tk = TTY::Tokenizer.new
      tk.feed("\e[1".to_slice).should be_empty
      tokens = tk.feed(";2m".to_slice)
      tokens.size.should eq(1)
      String.new(tokens[0].bytes).should eq("\e[1;2m")
    end

    it "emits SS2 and SS3" do
      kinds(TTY::Tokenizer.new.feed("\eN".to_slice)).should eq([TTY::Token::Kind::SS2])
      kinds(TTY::Tokenizer.new.feed("\eO".to_slice)).should eq([TTY::Token::Kind::SS3])
    end

    it "emits a bare two-byte ESC sequence" do
      tokens = TTY::Tokenizer.new.feed("\eM".to_slice)
      tokens[0].kind.should eq(TTY::Token::Kind::ESC)
      String.new(tokens[0].bytes).should eq("\eM")
    end
  end

  describe "string sequences" do
    it "terminates an OSC on BEL" do
      tokens = TTY::Tokenizer.new.feed("\e]0;title\a".to_slice)
      tokens[0].kind.should eq(TTY::Token::Kind::OSC)
      String.new(tokens[0].bytes).should eq("\e]0;title\a")
    end

    it "terminates a DCS on ST" do
      tokens = TTY::Tokenizer.new.feed("\ePq#0\e\\".to_slice)
      tokens[0].kind.should eq(TTY::Token::Kind::DCS)
      String.new(tokens[0].bytes).should eq("\ePq#0\e\\")
    end

    it "reinjects a non-ST byte after ESC inside a string body" do
      tokens = TTY::Tokenizer.new.feed("\e]0;a\e[1mb\a".to_slice)
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::OSC)
      String.new(tokens[0].bytes).should eq("\e]0;a\e[1mb\a")
    end
  end

  describe "trailing ESC" do
    it "holds a lone trailing ESC until more bytes arrive" do
      tk = TTY::Tokenizer.new
      tk.feed("\e".to_slice).should be_empty
      tokens = tk.feed("[0m".to_slice)
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::CSI)
    end

    it "flushes a lone trailing ESC as a malformed ESC token" do
      tk = TTY::Tokenizer.new
      tk.feed("\e".to_slice).should be_empty
      flushed = tk.flush
      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::ESC)
      flushed[0].malformed?.should be_true
      flushed[0].bytes.should eq(Bytes[0x1B])
    end

    it "flushes an incomplete CSI as malformed under its kind" do
      tk = TTY::Tokenizer.new
      tk.feed("\e[1;2".to_slice).should be_empty
      flushed = tk.flush
      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::CSI)
      flushed[0].malformed?.should be_true
      String.new(flushed[0].bytes).should eq("\e[1;2")
    end

    it "flushes an unterminated OSC as malformed under its kind" do
      tk = TTY::Tokenizer.new
      tk.feed("\e]0;partial".to_slice).should be_empty
      flushed = tk.flush
      flushed.size.should eq(1)
      flushed[0].kind.should eq(TTY::Token::Kind::OSC)
      flushed[0].malformed?.should be_true
    end

    it "flushes cleanly when nothing is held" do
      TTY::Tokenizer.new.flush.should be_empty
    end
  end

  describe "string cap" do
    it "caps an unterminated OSC and marks it malformed" do
      tk     = TTY::Tokenizer.new(string_limit: 16)
      tokens = tk.feed(("\e]0;" + "x" * 64).to_slice)

      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::OSC)
      tokens[0].malformed?.should be_true
      tokens[0].bytes.size.should eq(16)
    end

    it "discards the remainder of a capped string and recovers on terminator" do
      tk     = TTY::Tokenizer.new(string_limit: 16)
      tokens = tk.feed(("\e]0;" + "x" * 64 + "\a").to_slice)
      tokens.select(&.malformed?).size.should eq(1)

      following = tk.feed("hi".to_slice)
      following[0].kind.should eq(TTY::Token::Kind::Text)
      String.new(following[0].bytes).should eq("hi")
    end

    it "recovers a capped string on an ESC-backslash terminator" do
      tk = TTY::Tokenizer.new(string_limit: 16)
      tk.feed(("\eP" + "x" * 64).to_slice)
      tk.feed("\e\\".to_slice)

      following = tk.feed("ok".to_slice)
      String.new(following[0].bytes).should eq("ok")
    end

    it "caps an unterminated CSI" do
      tk     = TTY::Tokenizer.new(string_limit: 8)
      tokens = tk.feed(("\e[" + "1;" * 32).to_slice)
      tokens.size.should eq(1)
      tokens[0].kind.should eq(TTY::Token::Kind::CSI)
      tokens[0].malformed?.should be_true
    end
  end

  describe "reset" do
    it "clears held utf-8 and sequence state" do
      tk = TTY::Tokenizer.new
      tk.feed(Bytes[0xF0, 0x9F])
      tk.feed("\e[1".to_slice)
      tk.reset
      tk.flush.should be_empty

      tokens = tk.feed("ok".to_slice)
      String.new(tokens[0].bytes).should eq("ok")
    end
  end
end
