# tty

`tty` is a Crystal shard for Unix terminals and pseudo-terminals. It provides termios control, window size handling, terminal/session ioctls, readiness waits, PTY allocation, and child process lifecycle management on top of a small raw-syscall core.

## Features

- Termios get/set with input, output, control, and local flag enums
- Raw and cbreak helpers with scoped restoration
- Standard baud rates and Linux custom baud rates through `termios2`/`BOTHER`
- Window size get/set and resize notification
- Input/output queue inspection, break control, modem lines, and byte injection
- Session and foreground process-group helpers
- PTY open/close, master/slave fd access, and optional `IO::FileDescriptor` adapters
- PTY child spawning with readiness synchronization, signal-state reset, `wait`, timed `wait`, `terminate`, and `kill`
- Readiness waits using integer millisecond timeouts (`-1` waits forever, `0` polls once)
- Structured syscall errors with `errno`, `errno_name`, `operation`, `fd`, `path`, and `request`

## Requirements

- Crystal `>= 1.10.0`
- Linux or macOS on x86-64
- A C compiler for `src/ext/tty_syscall.s`

The shard uses a tiny assembly syscall trampoline. `shards install` runs the `postinstall` script and builds `src/ext/tty_syscall.o`.

## Installation

Use a local path dependency while developing:

```yaml
# shard.yml
dependencies:
  tty:
    path: ../tty
```

Then run:

```sh
shards install
```

In code:

```crystal
require "tty"
```

## Quick start

```crystal
require "tty"

process = TTY::PTY.spawn("sh", ["-c", "printf 'hello\\n'; exit 3"], env: {"PATH" => "/usr/bin:/bin"})

if process.pty.wait_readable(1000)
  buffer = Bytes.new(128)
  count = process.pty.read_master(buffer)
  puts String.new(buffer[0, count])
end

status = process.wait
puts status.exit_status
process.close
```

## Termios

```crystal
pty = TTY::PTY.open
original = pty.termios

raw = original
raw.make_raw
pty.termios = raw

pty.termios = original
pty.close
```

Scoped raw mode on an existing fd:

```crystal
TTY.raw(0) do
  byte = Bytes.new(1)
  TTY::Syscall.read(0, byte.to_unsafe, 1)
end
```

## Readiness

```crystal
TTY.wait_readable(fd, 1000)  # wait up to 1000 ms
TTY.wait_writable(fd, 0)     # poll once
TTY.wait_readable(fd, -1)    # wait forever
```

`TTY::PTY` instances also have `wait_readable(timeout_ms)` and `wait_writable(timeout_ms)`.

## Window size

```crystal
pty = TTY::PTY.open
pty.winsize = TTY::Winsize.new(24_u16, 80_u16)
puts pty.winsize.cols
pty.close
```

Resize notifications for a terminal fd:

```crystal
TTY.on_resize(0) do |size|
  puts "#{size.cols}x#{size.rows}"
end
```

## Process lifecycle

```crystal
process = TTY::PTY.spawn("sleep", ["30"], env: {"PATH" => "/usr/bin:/bin"})

if process.wait(100).nil?
  process.terminate
end

status = process.wait
status.signaled?
status.term_signal
process.close
```

`process.wait` blocks until exit. `process.wait(timeout_ms)` returns `TTY::ChildStatus?` and returns `nil` on timeout. `process.status` returns the cached status after a successful wait.

## Errors

```crystal
begin
  TTY::Syscall.read(-1, Bytes.new(1).to_unsafe, 1)
rescue ex : TTY::Syscall::Error
  puts ex.errno
  puts ex.errno_name
  puts ex.operation
  puts ex.fd
end
```

## Public API reference

### Top-level `TTY`

| API | Description |
| --- | --- |
| `TTY.termios(fd : Int32) : Termios` | Read terminal attributes from an fd. |
| `TTY.termios(io : IO::FileDescriptor) : Termios` | Read terminal attributes from an IO. |
| `TTY.winsize(fd : Int32) : Winsize` | Read window size from an fd. |
| `TTY.winsize(io : IO::FileDescriptor) : Winsize` | Read window size from an IO. |
| `TTY.raw(fd, action = SetAction::Now) { ... }` | Enable raw mode for the block, then restore. |
| `TTY.raw(io, action = SetAction::Now) { ... }` | IO overload of `raw`. |
| `TTY.cbreak(fd, action = SetAction::Now) { ... }` | Enable cbreak mode for the block, then restore. |
| `TTY.cbreak(io, action = SetAction::Now) { ... }` | IO overload of `cbreak`. |
| `TTY.flush(fd, queue = FlushQueue::Both) : Nil` | Flush input/output queues. |
| `TTY.on_resize(fd) { |winsize| ... } : Nil` | Trap `SIGWINCH` and yield the current size. |

### Readiness

| API | Description |
| --- | --- |
| `TTY.wait_readable(fd : Int32, timeout_ms : Int32 = -1) : Bool` | Wait until readable, HUP, or error. |
| `TTY.wait_writable(fd : Int32, timeout_ms : Int32 = -1) : Bool` | Wait until writable, HUP, or error. |
| `TTY.wait_io(fd : Int32, events : IOEvent, timeout_ms : Int32 = -1) : Bool` | Wait for an explicit event mask. |
| `TTY::IOEvent` | `Readable`, `Writable`. |
| `TTY::PollFd` | Low-level `pollfd` layout: `fd`, `events`, `revents`. |

`timeout_ms` is `-1` for infinite wait, `0` for a single poll, or a positive millisecond timeout.

### Termios types

| Type/API | Description |
| --- | --- |
| `TTY::SetAction` | `Now`, `Drain`, `Flush`; maps to `TCSETS`, `TCSETSW`, `TCSETSF`. |
| `TTY::FlushQueue` | `Input`, `Output`, `Both`. |
| `TTY::InputFlag` | Platform termios input flags. |
| `TTY::OutputFlag` | Platform termios output flags. |
| `TTY::ControlFlag` | Platform termios control flags. |
| `TTY::LocalFlag` | Platform termios local flags. |
| `TTY::ControlChar` | Platform control-character indexes such as `Min`, `Time`, `Intr`, `Quit`, `Start`, `Stop`. |
| `TTY::Baud` | Standard baud enum; Linux also has `BOther` for custom speeds. |
| `TTY::Termios.get(fd) : Termios` | Read attributes. |
| `Termios#set(fd, action = SetAction::Now) : Nil` | Write attributes. |
| `Termios#input`, `#output`, `#control`, `#local` | Get flag sets. |
| `Termios#input=`, `#output=`, `#control=`, `#local=` | Set flag sets. |
| `Termios#line`, `#line=` | Line discipline; no-op on Darwin. |
| `Termios#[cc]`, `#[]=(cc, value)` | Access control characters. |
| `Termios#baud`, `#baud=` | Standard baud get/set. |
| `Termios#custom_baud?` | True when Linux `BOther` is active; always false on Darwin. |
| `Termios#read_timeout`, `#read_timeout=` | `Time::Span?` mapped to `MIN`/`TIME`. |
| `Termios#make_raw`, `#make_cbreak` | Mutate the struct to raw/cbreak settings. |
| `Termios#to_s(io)` | Human-readable termios summary. |

Linux-only custom baud:

| API | Description |
| --- | --- |
| `TTY::Termios2.get(fd) : Termios2` | Read `termios2`. |
| `TTY::Termios2.from(termios : Termios) : Termios2` | Copy a `Termios` into `Termios2`. |
| `Termios2#set(fd, action = SetAction::Now) : Nil` | Write `termios2`. |
| `Termios2#input_speed`, `#output_speed` | Raw speed fields. |
| `Termios2#custom_baud=(rate : UInt32)` | Set `BOther` with a custom baud rate. |
| `Termios2#custom_baud?` | Whether `BOther` is active. |

### Window size

| API | Description |
| --- | --- |
| `TTY::Winsize.new(rows = 0, cols = 0, xpixel = 0, ypixel = 0)` | Create a size struct. |
| `Winsize#rows`, `#cols`, `#xpixel`, `#ypixel` | Mutable properties. |
| `TTY::Winsize.get(fd) : Winsize` | Read size. |
| `Winsize#set(fd) : Nil` | Write size. |

### Control and session

| API | Description |
| --- | --- |
| `TTY.pending_input(fd) : Int32` | Bytes available to read. |
| `TTY.pending_output(fd) : Int32` | Bytes still queued for output. |
| `TTY.inject(fd, byte : UInt8) : Nil` | Inject one input byte (`TIOCSTI`). |
| `TTY.send_break(fd) : Nil` | Assert break. |
| `TTY.clear_break(fd) : Nil` | Clear break. |
| `TTY.modem_status(fd) : ModemLine` | Read modem lines. |
| `TTY.set_modem_status(fd, lines : ModemLine) : Nil` | Write modem lines. |
| `TTY::ModemLine` | Flags: `LE`, `DTR`, `RTS`, `ST`, `SR`, `CTS`, `CD`, `RI`, `DSR`. |
| `TTY::Session.leader : Int32` | Call `setsid` in the current process. |
| `TTY::Session.make_controlling(fd) : Nil` | Make fd the controlling terminal (`TIOCSCTTY`). |
| `TTY::Session.foreground_pgrp(fd) : Int32` | Read foreground process group (`TIOCGPGRP`). |
| `TTY::Session.set_foreground_pgrp(fd, pgrp) : Nil` | Set foreground process group (`TIOCSPGRP`). |
| `TTY::Session.exclusive(fd, enable = true) : Nil` | Toggle exclusive terminal mode (`TIOCEXCL`/`TIOCNXCL`). |

### PTY

| API | Description |
| --- | --- |
| `TTY::PTY.open : PTY` | Allocate a PTY pair. |
| `TTY::PTY.spawn(command, args = [] of String, env = ENV.to_h, winsize = nil) : PTY::Process` | Spawn a child on a new PTY. |
| `TTY::PTY.wait(pid : Int32) : ChildStatus` | Blocking wait by pid. |
| `PTY#master_fd`, `#slave_fd`, `#slave_name` | Raw fds and slave path. |
| `PTY#closed? : Bool` | Whether master is closed. |
| `PTY#close_slave : Nil` | Close only the slave fd. |
| `PTY#close : Nil` | Idempotently close slave and master. |
| `PTY#master_io`, `#slave_io` | `IO::FileDescriptor` adapters. |
| `PTY#read_master(buffer)`, `#write_master(data)` | Master-side I/O. |
| `PTY#read_slave(buffer)`, `#write_slave(data)` | Slave-side I/O. |
| `PTY#wait_readable(timeout_ms = -1)`, `#wait_writable(timeout_ms = -1)` | PTY readiness. |
| `PTY#termios`, `#termios=` | Terminal attributes on the effective fd. |
| `PTY#winsize`, `#winsize=` | Window size. |

### PTY process

| API | Description |
| --- | --- |
| `PTY::Process#pid : Int32` | Child pid. |
| `PTY::Process#pty : PTY` | Owned PTY. |
| `PTY::Process#wait : ChildStatus` | Blocking wait; caches status. |
| `PTY::Process#wait(timeout_ms : Int32) : ChildStatus?` | Non-blocking/timed wait; `nil` on timeout. |
| `PTY::Process#status : ChildStatus?` | Cached status, if already known. |
| `PTY::Process#exited? : Bool` | Whether a status has been observed. |
| `PTY::Process#signal(signal : Int32) : Nil` | Send a raw signal number. |
| `PTY::Process#terminate : Nil` | Send `SIGTERM`. |
| `PTY::Process#kill : Nil` | Send `SIGKILL`. |
| `PTY::Process#close : Nil` | Close the owned PTY. |

### Child status

| API | Description |
| --- | --- |
| `ChildStatus#exited? : Bool` | Normal exit. |
| `ChildStatus#exit_status : Int32` | Exit code when `exited?`. |
| `ChildStatus#signaled? : Bool` | Terminated by a signal. |
| `ChildStatus#term_signal : Int32` | Terminating signal number. |
| `ChildStatus#stopped? : Bool` | Stopped by job control. |
| `ChildStatus#success? : Bool` | Exited with status `0`. |

### Errors

| API | Description |
| --- | --- |
| `TTY::Error` | Base shard error. |
| `TTY::PTY::Error` | PTY-specific error. |
| `TTY::Syscall::Error` | Syscall failure with context. |
| `Syscall::Error#errno`, `#errno_name` | Numeric errno and short name. |
| `Syscall::Error#operation`, `#fd`, `#path`, `#request` | Context fields; optional fields are `nil` when absent. |

### Low-level syscall module

`TTY::Syscall` is the escape hatch used by the public APIs. It is public, but most callers should prefer the higher-level wrappers.

| API | Description |
| --- | --- |
| `Syscall.read(fd, buffer, count)`, `write(fd, data)`, `close(fd)` | Basic fd operations. |
| `Syscall.ioctl(fd, request, arg)` | Pointer or integer ioctl. |
| `Syscall.openat(path, flags)` | Open relative to `AT_FDCWD`. |
| `Syscall.fork`, `dup2`, `setsid`, `kill`, `wait4`, `exit_group` | Process primitives. |
| `Syscall.poll(fds, nfds, timeout_ms)`, `sleep_ms(timeout_ms)` | Raw poll and poll-based sleep. |
| `Syscall.socketpair(domain, type, protocol, fds)` | Create a connected fd pair. |
| `Syscall.reset_child_signal_state` | Reset catchable handlers to default and clear the signal mask. |
| `Syscall.raw(nr, a1 = 0, a2 = 0, a3 = 0, a4 = 0)` | Direct trampoline call. |
| `Syscall.check(ret, operation = "syscall", fd = nil, path = nil, request = nil)` | Convert negative returns to `Syscall::Error`. |

Common constants include `WNOHANG`, `EINTR`, `EIO`, `EBADF`, `ECHILD`, `EAGAIN`, `AF_UNIX`, `SOCK_STREAM`, `SIGKILL`, `SIGTERM`, and `SIGSTOP`.

## Examples

Build all examples:

```sh
make examples
```

Example programs are written to `.build/examples`:

- `termios`
- `readiness`
- `pty_process`
- `winsize`
- `control`
- `session`
- `errors`

## Development

```sh
make spec       # run the spec suite
make examples   # compile example programs
make clean      # remove syscall object and example binaries
```

## Notes

- The newer core APIs use raw values: `Int32` fds, integer millisecond timeouts, and integer signal numbers.
- Some convenience APIs still use Crystal stdlib types, including `IO::FileDescriptor`, `Time::Span` for termios read timeouts, `ENV` as the default spawn environment, and `Signal::WINCH` for resize callbacks.
- `TTY::PTY.spawn` resets catchable child signal handlers to default and clears the signal mask before `execve`, then synchronizes with the parent so immediate `terminate`/`kill` calls are reliable.
- `TTY::Session.leader` calls `setsid`; use it only in a process that is not already a process-group leader.

## License

MIT
