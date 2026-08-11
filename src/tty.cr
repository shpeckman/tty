# src/tty.cr
require "./tty/lib_c"
require "./tty/terminal"
require "./tty/pty"

module TTY
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
