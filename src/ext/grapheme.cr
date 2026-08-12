# src/ext/grapheme.cr
require "unicode_grapheme"

# Usage
# -----
#
#   UW.each("héllo 🇧🇪") do |cluster, width|
#     puts "#{String.new(cluster)} (#{width})"
#   end
#
# Three operations, each with a `String` and a `Bytes` overload:
#
#   UW.each(input) { |cluster : Bytes, width : Int32| }
#   UW.width(input) : Int32
#   UW.count(input) : Int32
#
#   UW.count("e\u0301a\u0301")             # => 2
#   UW.count("\u{1F468}\u200D\u{1F469}")   # => 1
#
#   UW.width("hello")                      # => 5
#   UW.width("\u4E00")                     # => 2
#   UW.width("e\u0301")                    # => 1
#   UW.width("\u{1F1FA}\u{1F1F8}")         # => 2
#   UW.width("\t")                         # => 0

# Cluster slices
# --------------
#
# `each` yields `Bytes` views into the original buffer.
# Nothing is copied, so a cluster is only valid for as long as the
# input is.
#
# Materialize with `String.new(cluster)` if you need to keep it:
#
#   clusters = [] of String
#   UW.each(line) { |cluster, _| clusters << String.new(cluster) }

# Width policy
# ------------
#
# Width is computed per cluster, not per codepoint, which is why a flag
# or a family emoji is two columns rather than the sum of its parts.
#
#   Cluster                                             Columns
#   --------------------------------------------------  -------
#   Control, CR, LF                                     0
#   Contains an East Asian Wide or Fullwidth codepoint  2
#   Regional indicator (flag)                           2
#   Extended pictographic followed by U+FE0F            2
#   Everything else                                     1
#
# Combining marks, joiners and variation selectors add nothing on their own,
# so a base character with any number of marks attached stays at the width
# of its base.

# Invalid input
# -------------
#
# `Bytes` input is not assumed to be well-formed UTF-8. Overlong encodings,
# surrogates, out-of-range values and truncated sequences are each treated
# as a single-byte cluster, so iteration always advances and never loops:
#
#   UW.each(Bytes[0xFF, 0x41]) { |cluster, _| p cluster.to_a }
#   # => [255]
#   # => [65]
