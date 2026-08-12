# src/tty/interceptor.cr
require "./vt"
require "../ext/mvu"

module TTY
  # An Interceptor allows hooking into the raw data streams and parsed token
  # streams of a PTY. This is primarily useful for implementing custom ANSI
  # protocols, proxying, or recording I/O.
  #
  # NOTE: `on_pty_read` and `intercept` are executed concurrently in the read fiber,
  # while `on_pty_write` is executed in the main MVU update fiber.
  abstract class Interceptor
    @dispatch : Proc(MVU::Msg, Nil)?

    # Binds the MVU dispatch function, allowing the interceptor to emit its own
    # MVU messages (e.g., when a custom protocol sequence is fully assembled).
    def bind_dispatch(dispatch : Proc(MVU::Msg, Nil)) : Nil
      @dispatch = dispatch
    end

    # Helper to emit an MVU message from within the interceptor.
    protected def dispatch(msg : MVU::Msg) : Nil
      @dispatch.try(&.call(msg))
    end

    # Invoked with raw bytes immediately after they are read from the PTY,
    # before they hit the VT parser.
    def on_pty_read(data : Bytes) : Nil
    end

    # Invoked with raw bytes immediately before they are written to the PTY.
    def on_pty_write(data : Bytes) : Nil
    end

    # Invoked with each parsed token from the PTY.
    # Return the `token` to allow it to pass through to the application,
    # return a modified `Token`, or return `nil` to swallow it completely.
    def intercept(token : TTY::VT::Token) : TTY::VT::Token?
      token
    end
  end
end
