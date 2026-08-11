# src/tty/lib_c.cr

# These blocks must reopen the *top-level* `LibC`, not a module-nested one, so
# the stdlib aliases like `LibC::UShort`/`LibC::ModeT` resolve and the bindings
# merge with the stdlib's. They therefore live outside `TTY`.
@[Link("c")]
lib LibC
  {% unless LibC.has_constant?(:Winsize) %}
    struct Winsize
      ws_row : LibC::UShort
      ws_col : LibC::UShort
      ws_xpixel : LibC::UShort
      ws_ypixel : LibC::UShort
    end
  {% end %}

  {% unless LibC.has_method?(:ioctl) %}
    fun ioctl(fd : LibC::Int, request : LibC::ULong, ...) : LibC::Int
  {% end %}

  {% unless LibC.has_constant?(:TCSANOW) %}
    TCSANOW = 0
  {% end %}

  {% unless LibC.has_constant?(:Termios) %}
    struct Termios
      c_iflag : UInt32
      c_oflag : UInt32
      c_cflag : UInt32
      c_lflag : UInt32
      c_line : UInt8
      c_cc : UInt8[32]
      c_ispeed : UInt32
      c_ospeed : UInt32
    end
  {% end %}

  {% unless LibC.has_method?(:tcgetattr) %}
    fun tcgetattr(fd : LibC::Int, termios_p : Termios*) : LibC::Int
  {% end %}
  {% unless LibC.has_method?(:tcsetattr) %}
    fun tcsetattr(fd : LibC::Int, optional_actions : LibC::Int, termios_p : Termios*) : LibC::Int
  {% end %}
  {% unless LibC.has_method?(:cfmakeraw) %}
    fun cfmakeraw(termios_p : Termios*) : Void
  {% end %}

  fun posix_spawn(pid : LibC::PidT*, path : LibC::Char*,
                  file_actions : Void*, attrp : Void*,
                  argv : LibC::Char**, envp : LibC::Char**) : LibC::Int
  fun posix_spawnp(pid : LibC::PidT*, file : LibC::Char*,
                   file_actions : Void*, attrp : Void*,
                   argv : LibC::Char**, envp : LibC::Char**) : LibC::Int

  fun posix_spawn_file_actions_init(fa : Void*) : LibC::Int
  fun posix_spawn_file_actions_destroy(fa : Void*) : LibC::Int
  fun posix_spawn_file_actions_addopen(fa : Void*, fildes : LibC::Int,
                                       path : LibC::Char*, oflag : LibC::Int,
                                       mode : LibC::ModeT) : LibC::Int
  fun posix_spawn_file_actions_adddup2(fa : Void*, fildes : LibC::Int,
                                       newfildes : LibC::Int) : LibC::Int
  fun posix_spawn_file_actions_addclose(fa : Void*, fildes : LibC::Int) : LibC::Int

  fun posix_spawnattr_init(attr : Void*) : LibC::Int
  fun posix_spawnattr_destroy(attr : Void*) : LibC::Int
  fun posix_spawnattr_setflags(attr : Void*, flags : LibC::Short) : LibC::Int
end

@[Link("util")]
lib LibC
  fun openpty(amaster : LibC::Int*, aslave : LibC::Int*, name : LibC::Char*,
              termp : Void*, winp : LibC::Winsize*) : LibC::Int
end
