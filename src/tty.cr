# src/tty.cr
require "./ext/vt"
require "./ext/mvu"
require "./tty/winsize"
require "./tty/modes"
require "./tty/messages"
require "./tty/interceptor"
require "./tty/pty"
require "./tty/codec/gfx"

module TTY
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
