# src/tty.cr
require "./tty/pty"
require "./tty/mux"

module TTY
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
