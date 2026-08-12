# src/tty/vt.cr

# Usage
# -----
#
#   parser = VT::Parser.new
#   parser.parse("\e[31mHello\e[0m") do |token|
#     p token.kind
#   end
#
# Two parsing operations are available, returning arrays or yielding to a block:
#
#   parser.parse(input) { |token : VT::Token| }
#   parser.parse(input) : Array(VT::Token)
#
# Token API
# ---------
#
# Every parsed token exposes the following methods to inspect and consume its data:
#
#   token.kind         : Kind      # The token category (Text, C0, CSI, OSC, etc.)
#   token.bytes        : Bytes     # The raw underlying byte slice
#   token.malformed?   : Bool      # True if the token was truncated or invalid
#   token.size         : Int32     # Number of bytes in the token
#   token.empty?       : Bool      # True if the token has 0 bytes
#   token.text?        : Bool      # True if kind is Text
#   token.control?     : Bool      # True if kind is C0
#   token.sequence?    : Bool      # True if not Text and not C0
#   token.string?      : Bool      # True if kind is OSC, DCS, APC, PM, or SOS
#   token.clone        : Token     # Creates a new Token that owns a copy of the bytes
#   token.each_byte { |b| }        # Yields each byte in the token
#   token[index]       : UInt8     # Returns the byte at the given index
#   token.to_slice     : Bytes     # Alias for `bytes`
#   token.to_s(io)     : Nil       # Writes the raw bytes to the given IO
#   token.inspect(io)  : Nil       # Writes a human-readable representation to the IO
#   token == other     : Bool      # Compares kind, malformed status, and bytes
#
# State Retention & Flushing
# --------------------------
#
# The parser is stateful. It seamlessly buffers incomplete UTF-8 codepoints and
# partial escape sequences across multiple `parse` calls.
#
#   parser.parse("\e")   # => []
#   parser.parse("[m")   # => [VT::Token(CSI, ...)]
#
# When you reach the end of the input stream, use `flush` to force the emission
# of any trailing incomplete bytes.
#
#   parser.parse("\e[1;")
#   parser.flush         # => [VT::Token(CSI, malformed: true)]
#
# Invalid Input
# -------------
#
# Sequences that exceed the parser's internal capacity, are improperly terminated,
# or contain invalid UTF-8 codepoints will still be emitted, but with their
# `malformed?` flag set to true.

require "./vt/token"
require "./vt/tables"
require "./vt/parser"