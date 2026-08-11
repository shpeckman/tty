# src/tty.cr
require "./ext/mvu"
require "./tty/winsize"
require "./tty/raw_mode"
require "./tty/token"
require "./tty/tokenizer"
require "./tty/messages"
require "./tty/pty"

module TTY
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
