# src/tty.cr
require "./ext/mvu"
require "./tty/winsize"
require "./tty/raw_mode"
require "./tty/cbreak_mode"
require "./tty/token"
require "./tty/parser"
require "./tty/messages"
require "./tty/pty"
require "./tty/codec/gfx"

module TTY
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
