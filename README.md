# tty

A small Crystal shard for driving pseudo-terminals. It gives a child process a
real controlling terminal — as a session leader on a fresh `pts` device — and
shuttles bytes to and from its master fd. A multiplexer sits on top for owning
many sessions at once behind a single tagged output stream.

- **`TTY::Pty`** — one PTY-backed child process, spawned with a controlling
  terminal via `posix_spawn` + `POSIX_SPAWN_SETSID` (falling back to `setsid`).
- **`TTY::Mux`** — a single-owner supervisor for many `Pty` sessions, exposing
  them through one `Channel` of tagged frames.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  tty:
    github: shpeckman/tty
```

Then run `shards install`.

Requires Crystal `>= 1.21.0` and links against `libutil` (for `openpty`), which
is present on Linux, macOS, and the BSDs.

## Quick start

```cr
require "tty"

pty = TTY::Pty.new("/bin/sh", ["-i"], cols: 80, rows: 24)

pty.write "echo hello\n"
pty.write "exit\n"

buffer = Bytes.new(4096)
loop do
  n = pty.master.read(buffer)
  break if n.zero?
  STDOUT.write buffer[0, n]
end

pty.reap
```

## `TTY::Pty`

A single child process attached to a pseudo-terminal. The child is opened as a
session leader with the slave `pts` as its controlling terminal, so job control,
signals, and full-screen (curses) programs behave exactly as they would under a
real terminal.

```cr
pty = TTY::Pty.new(
  "/bin/bash",
  ["-i"],
  cols: 120,
  rows: 40,
  env: {"TERM" => "xterm-256color"},
  chdir: "/tmp",
)
```

### Constructor

`TTY::Pty.new(command, args = [], cols = 80, rows = 24, env = nil, chdir = nil)`

Opens a master/slave pair with the given window size and spawns `command`. The
preferred spawn path uses `posix_spawn` with `POSIX_SPAWN_SETSID` and file
actions that wire the slave onto fds 0, 1, and 2 and close the master in the
child; if the executable can't be resolved it falls back to spawning through
`setsid -c`. `env` layers over the current environment, and a `nil` value
removes a variable.

### Methods

- `master : IO::FileDescriptor` — the master end. Read it for child output,
  though prefer `write` for input.
- `process : Process` — the spawned child.
- `write(data : Bytes | String) : Nil` — send input to the child and flush.
- `resize(cols, rows) : Nil` — update the terminal window size (`TIOCSWINSZ`).
  Wire this to `SIGWINCH` to track the host terminal.
- `reap : Int32?` — wait for the child and return its exit code (`nil` if it was
  signalled). Idempotent; safe to call more than once.
- `kill : Nil` — send `SIGHUP` to the child and close the master. Idempotent.
- `closed? : Bool` — whether `kill` has run.

## `TTY::Mux`

Owns many `Pty` sessions and forwards their bytes to one tagged output stream
without interpreting the data. A single owner fiber is the sole mutator of the
session map: callers send commands and per-session pumps report exits, both
serialized through a `select`, so no lock is needed. Output frames bypass the
owner and go straight to the public channel, so a slow consumer only applies
backpressure to the offending session's pump — command handling stays live.

```cr
mux = TTY::Mux.new

result = mux.spawn_session("/bin/sh", ["-i"], cols: 80, rows: 24)
raise result.error.not_nil! if result.error
id = result.id.not_nil!

mux.write id, "uptime\n"

spawn do
  while frame = mux.output.receive?
    case frame.kind
    in TTY::Mux::Kind::Output
      STDOUT.write frame.data
      STDOUT.flush
    in TTY::Mux::Kind::Exited
      puts "session #{frame.id} exited: #{frame.exit_code.inspect}"
    end
  end
end

sleep 1.second
mux.close
```

### Frames

`mux.output` is a `Channel(TTY::Mux::Frame)`. Each `Frame` carries an `id`, a
`kind`, and either data or an exit code:

- `Kind::Output` — `data : Bytes` holds a freshly copied slice of child output.
- `Kind::Exited` — `exit_code : Int32?` holds the reaped code (`nil` if
  signalled). The session has been removed from the map by the time this frame
  arrives.

The channel is closed once every pump has drained after `close`, so a
`while frame = mux.output.receive?` loop terminates cleanly.

### Methods

- `spawn_session(command, args = [], cols = 80, rows = 24, env = nil, chdir = nil) : SpawnResult`
  — spawn a session and block until the owner has processed it. On success
  `SpawnResult#id` is the new id; on failure `#error` holds the message and
  `#id` is `nil`. A failed spawn never unwinds the owner fiber.
- `write(id, data : Bytes | String) : Nil` — forward input. Dropped silently on
  an unknown or already-exited id.
- `resize(id, cols, rows) : Nil` — resize a session. Dropped silently on an
  unknown id.
- `kill(id) : Nil` — hang up one session. Its pump emits the `Exited` frame and
  the owner removes the entry.
- `close : Nil` — kill every session, stop the owner, and close `output` once
  all pumps have drained. Idempotent.
- `output : Channel(Frame)` — the public tagged output stream.
- `closed? : Bool` — whether `close` has run.

## Example

`examples/demo.cr` hands your real terminal to a child shell: it puts the host
terminal into raw mode, forwards keystrokes to the PTY master, pumps child
output back to stdout, and relays `SIGWINCH` resizes. The child owns the
terminal, so job control and full-screen programs work.

```console
crystal run examples/demo.cr
```

Either side reaching EOF tears down the session, restores the terminal, and
prints the child's exit code.

## Testing

The specs are standalone runners driven through the Makefile:

```console
make test
```

- `spec/ctty_test.cr` verifies the child is a session leader with a `/dev/pts/*`
  controlling terminal.
- `spec/jobcontrol_test.cr` verifies an interactive shell does not report job
  control as disabled.

## License

MIT. See [LICENSE](LICENSE).