# src/tty.cr
require "./tty/winsize"
require "./tty/raw_mode"
require "./tty/token"
require "./tty/tokenizer"
require "./tty/messages"
require "./tty/pty"
require "./tty/gfx"

module TTY
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
