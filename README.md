# tty

`tty` is a Crystal shard for Unix terminals and pseudo-terminals. It provides termios control, window size handling, terminal/session ioctls, readiness waits, PTY allocation, packet mode, process lifecycle management, pidfds, and event polling on top of a raw-syscall core.

## Features

- Inline Crystal syscall trampoline with zero-through-six-argument calls
- Termios get/set with input, output, control, and local flag enums
- Raw and cbreak helpers with scoped restoration, including on exceptions
- Macro API: declarative termios configuration, scoped terminal state, and a spawn DSL, with flag names validated at compile time
- Standard baud rates and Linux custom baud rates through `termios2`/`BOTHER`
- File descriptor flags, nonblocking mode, close-on-exec, pipes, `dup3`, `fstat`, vectored I/O, and `close_range` with a `/proc/self/fd` fallback for older kernels
- Zero-copy transfers with `splice`, `tee`, and `copy_file_range` on Linux
- Single-fd and multi-fd readiness waits using integer millisecond timeouts
- Poller abstraction with `poll`, Linux `epoll`, and Darwin `kqueue` backends
- Window size get/set, resize notification, current-size query, and size propagation between terminals
- Input/output queue inspection, drain, break control, software flow control, modem lines, serial counters, and byte injection
- Session, controlling-terminal, foreground process-group, process-group, line-discipline, and exclusive-mode helpers
- PTY open/close, Linux `TIOCGPTPEER`, master/slave fd access, and optional `IO::FileDescriptor` adapters
- Fiber-aware `PTY::IO` that integrates the master with the Crystal event loop
- Configurable end-of-stream behavior for master reads after child exit
- PTY packet mode with data and control packet parsing
- PTY child spawning with exec error reporting, working-directory support, fd cleanup, full signal-state reset, `wait`, timed `wait`, `terminate`, and `kill`
- Linux `waitid` child events for exit, signal, core dump, stop, continue, and trap states, composable with `wait`
- Linux pidfd creation, exit polling, pidfd-based signals, and pidfd-backed timed waits
- Structured syscall errors with `errno`, `errno_name`, `operation`, `fd`, `path`, and `request`

## Requirements

- Crystal `>= 1.10.0`
- x86-64
- Linux for the complete feature set
- macOS for the compile-gated best-effort backend

Linux is the primary target and receives the complete runtime coverage. The macOS backend includes direct-syscall and `kqueue` paths, but direct kernel syscall compatibility on macOS is best-effort. Linux-only APIs are unavailable or raise `TTY::Error` on Darwin.

The shard itself does not require a C compiler or a postinstall build.

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  tty:
    github: shpeckman/tty
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

## File descriptors

`TTY::FD` provides direct fd helpers. Top-level convenience methods are available for nonblocking and close-on-exec flags.

```crystal
read_fd, write_fd = TTY::FD.pipe
TTY.set_nonblocking(read_fd)
TTY::FD.cloexec?(write_fd)

TTY::Syscall.write(write_fd, "hello")
buffer = Bytes.new(5)
TTY::Syscall.read(read_fd, buffer.to_unsafe, buffer.size)

TTY::Syscall.close(read_fd)
TTY::Syscall.close(write_fd)
```

Vectored I/O:

```crystal
written = TTY::FD.writev(fd, ["he".to_slice, "llo".to_slice])
first = Bytes.new(2)
second = Bytes.new(3)
read = TTY::FD.readv(fd, [first, second])
```

Zero-copy transfers (Linux-only; one side of `splice`/`tee` must be a pipe, `copy_file_range` works on regular files):

```crystal
TTY::FD.splice(read_fd, write_fd, 4096)
TTY::FD.tee(read_fd, write_fd, 4096)
TTY::FD.copy_file_range(source_fd, target_fd, 4096)
```

`TTY::FD.close_range(first, last)` closes an fd range in one syscall and falls back to walking `/proc/self/fd` on kernels without `close_range` or under restrictive seccomp policies.

## Readiness

Single-fd waits:

```crystal
TTY.wait_readable(fd, 1000)
TTY.wait_writable(fd, 0)
TTY.wait_priority(fd, -1)
```

Multi-fd polling:

```crystal
fds = [
  TTY::PollFd.watch(first_fd, TTY::IOEvent::Readable),
  TTY::PollFd.watch(second_fd, TTY::IOEvent::Readable),
]

ready = TTY.poll(fds, 1000)
fds.each do |fd|
  puts "#{fd.fd}: readable=#{fd.readable?} hup=#{fd.hangup?}"
end
```

`timeout_ms` is `-1` for an infinite wait, `0` for a single poll, or a positive millisecond timeout.

## Poller

`TTY::Poller` provides a small event-loop abstraction. The default backend is `epoll` on Linux and `kqueue` on Darwin. `PollerBackendKind::Poll` selects the portable `poll` backend explicitly.

```crystal
poller = TTY::Poller.new
poller.watch(fd, TTY::IOEvent::Readable)

events = poller.wait(1000)
events.each do |event|
  puts event.fd if event.readable?
end

poller.close
```

Explicit backend selection:

```crystal
poller = TTY::Poller.new(TTY::PollerBackendKind::Poll)
```

## PTY packet mode

Packet mode makes master-side reads return either a data packet or a control packet. Control packets report events such as queue flushes and output stop/start changes.

```crystal
pty = TTY::PTY.open
pty.packet_mode = true
pty.write_slave("hello")

buffer = Bytes.new(128)
packet = pty.read_packet(buffer)

if packet.data?
  puts String.new(buffer[0, packet.size])
elsif packet.control?
  puts packet.events
end

pty.close
```

`PTY#wait_priority(timeout_ms)` waits for priority data such as packet-mode control information.

## Evented I/O

`PTY::IO` adapts the master fd into a Crystal `IO` integrated with the event loop. Reads and writes suspend the current fiber instead of blocking the thread, so other fibers keep running while a read waits for child output.

```crystal
process = TTY::PTY.spawn("sh", ["-c", "sleep 1; echo done"], env: {"PATH" => "/usr/bin:/bin"})
io = process.pty.io

spawn do
  sleep 0.5.seconds
  puts "other work happens while the read is pending"
end

puts io.gets
process.wait
process.close
```

The wrapper is buffered, so call `io.flush` (or enable `flush_on_newline`) after writes that must reach the child immediately. `read_timeout` and `write_timeout` map to `IO::TimeoutError`.

Notes:

- Only one `PTY::IO` may exist per `PTY`; `PTY#io` raises `PTY::Error` on a second attempt.
- Creating a `PTY::IO` puts the master fd into nonblocking mode. Avoid mixing raw `read_master`/`write_master` calls with an active evented IO on the same PTY.
- Closing the `PTY::IO` closes the PTY, and closing the PTY closes the IO; either order is safe.
- After the child exits and the slave side is gone, reads report end-of-stream instead of raising `EIO` (see `PTY#eof_on_error` below).

## Process lifecycle

Basic lifecycle:

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

`process.wait` blocks until exit. `process.wait(timeout_ms)` returns `TTY::ChildStatus?` and returns `nil` on timeout; when a pidfd is available the timed wait sleeps on the pidfd instead of polling, so it returns promptly at exit. `process.status` returns the cached terminal status after a successful wait.

The default spawn environment inherits `ENV` and adds a `TERM` fallback (`xterm-256color`) when the parent has none, so curses-style programs work out of the box. Passing an explicit `env:` disables the fallback.

Spawn options:

```crystal
options = TTY::SpawnOptions.new(
  env: {"PATH" => "/usr/bin:/bin"},
  winsize: TTY::Winsize.new(24_u16, 80_u16),
  working_dir: "/tmp",
  close_fds: true,
)

process = TTY::PTY.spawn("pwd", [] of String, options)
```

Named options are also available:

```crystal
process = TTY::PTY.spawn("pwd", working_dir: "/tmp", env: {"PATH" => "/usr/bin:/bin"})
```

Exec failures raise `TTY::PTY::ExecError` and include the attempted paths and final `errno`:

```crystal
begin
  TTY::PTY.spawn("missing-command", env: {"PATH" => "/missing"})
rescue ex : TTY::PTY::ExecError
  puts ex.errno_name
  puts ex.attempts
end
```

Linux child events use `waitid` and can report stop and continue transitions:

```crystal
process = TTY::PTY.spawn("sleep", ["30"])
event = process.wait_event(100)

if event.nil?
  process.terminate
  event = process.wait_event
end

event.signaled?
event.term_signal
process.close
```

`wait_event` peeks with `WNOWAIT` and reaps terminal children through `wait4`, so `wait_event` and `wait` can be mixed in either order: whichever observes termination first records both the cached status and the terminal event, and the other returns the recorded value. Timed `wait_event` polls with `WNOHANG` because pidfds do not signal stop/continue transitions.

Linux pidfds provide pollable process references and pidfd-based signals:

```crystal
process = TTY::PTY.spawn("sleep", ["30"])
process.poll_exit(0)
process.terminate
process.poll_exit(1000)
process.wait
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

Scoped cbreak mode:

```crystal
TTY.cbreak(0) do
  byte = Bytes.new(1)
  TTY::Syscall.read(0, byte.to_unsafe, 1)
end
```

## Window size

```crystal
pty = TTY::PTY.open
pty.winsize = TTY::Winsize.new(24_u16, 80_u16)
puts pty.winsize.cols
pty.close
```

Query the size of an existing terminal; returns `nil` when the fd is not a terminal:

```crystal
size = TTY::Winsize.current(0)
puts size.try(&.cols)
```

Keep a PTY in sync with a real terminal: apply the current size immediately and follow `SIGWINCH`:

```crystal
TTY::Winsize.propagate(0, pty.master_fd)
```

Resize notifications for a terminal fd:

```crystal
TTY.on_resize(0) do |size|
  puts "#{size.cols}x#{size.rows}"
end
```

## Concurrency

The raw methods (`Syscall.*`, `PTY#read_master`, `PTY::Process#wait`, and friends) issue blocking syscalls directly. In the default single-threaded runtime a blocking syscall stalls every fiber on the thread until it returns:

- Use `PTY::IO` (`PTY#io`) for master-side I/O; it reads and writes through the Crystal event loop and suspends only the calling fiber. It may be shared across fibers (stdlib `IO` synchronization applies).
- Use `process.wait(timeout_ms)`, `process.wait_event(timeout_ms)`, and `PTY#wait_readable` to bound waits; the timed loops sleep fiber-locally, so other fibers keep running.
- Under multithreading (`-Dpreview_mt` or additional execution contexts) blocking calls only stall their own thread.

Ownership rules:

- A `PTY`, `Poller`, or `PTY::Process` instance is not internally synchronized; have one fiber own it at a time, or add your own synchronization.
- `PTY#close` closes the evented `PTY::IO` and any `master_io`/`slave_io` adapters, and closing those closes the PTY; a reader blocked in another fiber wakes with `IO::Error` ("Closed stream").
- Never close an fd with `Syscall.close` while it is registered with the Crystal event loop (for example through `PTY::IO` or an adopted `IO::FileDescriptor`); close the `IO` instead. Closing the fd underneath the runtime leaves a stale event-loop registration that poisons the next fd to reuse the same number.

Signal and child-reaping interplay with the runtime:

- Crystal's runtime traps `SIGCHLD` globally and reaps terminated children with `waitpid(-1, WNOHANG)` whenever the scheduler switches fibers. `PTY::Process#wait` and `#wait_event` detect the resulting `ECHILD` and reclaim the status recorded by the runtime, so they still return the exact exit status. The status is only unrecoverable when the child is reaped outside both this shard and the runtime (for example by calling `waitpid` on the pid directly); waits then raise `Syscall::Error` with `ECHILD`.
- `TTY.on_resize` and `Winsize.propagate` install `Signal::WINCH.trap` handlers that capture the given fd for the lifetime of the process. Trapping replaces any previous `SIGWINCH` handler (last registration wins), and the captured fd number must stay valid: once closed, a recycled fd with the same number receives the window-size writes.
- `PTY.spawn`'s child path between `fork` and `execve` is allocation-free by design (raw `fork` skips the runtime's `at_fork` handlers). Keep it that way when modifying the spawn path: no heap allocation, no locks, and no stdlib calls before `execve`.

## Macro API

The macro layer is compile-time only: it expands to the same `Termios`, `FD`, and `PTY.spawn` calls used by the imperative API, so there is no runtime cost. Flag and field names are validated during macro expansion; an unknown name fails the build with the list of valid values.

Declarative termios configuration with `TTY.configure`; only declared changes are applied on top of the current terminal state:

```crystal
TTY.configure(STDIN.fd) do
  raw                    # or cbreak; applies Termios#make_raw / #make_cbreak
  local -Echo, -ICanon   # unary +/- on InputFlag, OutputFlag, ControlFlag, LocalFlag members
  input +ICrNl           # repeated statements accumulate
  cc min: 1, time: 0     # ControlChar entries, lowercase named arguments
  baud B9600             # a TTY::Baud member
  action :drain          # :now (default), :drain or :flush, mapping to SetAction
end
```

Scoped terminal state with `TTY.with_terminal`; termios and fd status flags are snapshotted and restored in `ensure`, including when the block raises. The block value is returned:

```crystal
TTY.with_terminal(STDIN.fd, raw: true, nonblocking: true) do
  # ...
end
```

`raw` and `cbreak` are mutually exclusive; `nonblocking` accepts `true` or `false`. With no options, `with_terminal` only restores what it changed, so `TTY.with_terminal(fd, nonblocking: true)` skips the termios ioctls entirely.

Spawn DSL wrapping `PTY.spawn`:

```crystal
process = TTY.spawn("sh", ["-c", "ls"]) do
  env path: "/usr/bin:/bin", term: "xterm-256color"
  winsize rows: 24, cols: 80
  working_dir "/tmp"
  close_fds true
end
```

Declared environment entries merge with `SpawnOptions.default_env`. Named-argument keys must be lowercase identifiers in Crystal, so `env` upcases its keys (`env path: ...` sets `PATH`); pass a hash literal for exact-case keys: `env({"foo" => "bar"})`.

## Public API reference

### Top-level `TTY`

**`TTY.termios(fd : Int32) : Termios`**  
Read terminal attributes from an fd.

**`TTY.termios(io : IO::FileDescriptor) : Termios`**  
Read terminal attributes from an IO.

**`TTY.winsize(fd : Int32) : Winsize`**  
Read window size from an fd.

**`TTY.winsize(io : IO::FileDescriptor) : Winsize`**  
Read window size from an IO.

**`TTY.nonblocking?(fd) : Bool`**  
Read `O_NONBLOCK`.

**`TTY.set_nonblocking(fd, enabled = true) : Nil`**  
Set or clear `O_NONBLOCK`.

**`TTY.cloexec?(fd) : Bool`**  
Read `FD_CLOEXEC`.

**`TTY.set_cloexec(fd, enabled = true) : Nil`**  
Set or clear `FD_CLOEXEC`.

**`TTY.raw(fd, action = SetAction::Now) { ... }`**  
Enable raw mode for the block, then restore.

**`TTY.raw(io, action = SetAction::Now) { ... }`**  
IO overload of `raw`.

**`TTY.cbreak(fd, action = SetAction::Now) { ... }`**  
Enable cbreak mode for the block, then restore.

**`TTY.cbreak(io, action = SetAction::Now) { ... }`**  
IO overload of `cbreak`.

**`TTY.configure(fd) { ... }`**  
Macro: declarative termios configuration; expands to `Termios` get/mutate/set.

**`TTY.with_terminal(fd, raw: false, cbreak: false, nonblocking: nil) { ... }`**  
Macro: scoped termios and fd-flag state with guaranteed restoration.

**`TTY.spawn(command, args = [] of String) { ... }`**  
Macro: spawn DSL; expands to `PTY.spawn` with the declared options.

**`TTY.flush(fd, queue = FlushQueue::Both) : Nil`**  
Flush input/output queues.

**`TTY.on_resize(fd) { |winsize| ... } : Nil`**  
Trap `SIGWINCH` and yield the current size.

### File descriptors

**`TTY::FD.status_flags(fd) : Int32`**  
Read file status flags.

**`TTY::FD.descriptor_flags(fd) : Int32`**  
Read file descriptor flags.

**`TTY::FD.nonblocking?(fd) : Bool`**  
Whether `O_NONBLOCK` is set.

**`TTY::FD.set_nonblocking(fd, enabled = true) : Nil`**  
Set or clear `O_NONBLOCK`.

**`TTY::FD.cloexec?(fd) : Bool`**  
Whether `FD_CLOEXEC` is set.

**`TTY::FD.set_cloexec(fd, enabled = true) : Nil`**  
Set or clear `FD_CLOEXEC`.

**`TTY::FD.pipe(cloexec = true) : Tuple(Int32, Int32)`**  
Create a pipe.

**`TTY::FD.dup3(old_fd, new_fd, cloexec = true) : Nil`**  
Duplicate to an exact fd. Linux-only.

**`TTY::FD.duplicate_cloexec(fd, minimum_fd = 0) : Int32`**  
Duplicate with close-on-exec.

**`TTY::FD.close_range(first, last = Int32::MAX) : Nil`**  
Close a range of fds, falling back to a `/proc/self/fd` walk when `close_range` is unavailable. Linux-only.

**`TTY::FD.splice(from, to, count, flags = 0) : Int32`**  
Move bytes between fds without copying through userspace; one side must be a pipe. Linux-only.

**`TTY::FD.tee(from, to, count, flags = 0) : Int32`**  
Duplicate pipe data into another pipe without consuming it. Linux-only.

**`TTY::FD.copy_file_range(from, to, count) : Int32`**  
Copy bytes between regular files in-kernel. Linux-only.

**`TTY::FD.stat(fd)`**  
Read Linux stat metadata. Linux-only.

**`TTY::FD.mode(fd) : UInt32`**  
Read the file mode. Linux-only.

**`TTY::FD.character_device?(fd) : Bool`**  
Whether fd is a character device. Linux-only.

**`TTY::FD.readv(fd, buffers) : Int32`**  
Vectored read.

**`TTY::FD.writev(fd, buffers) : Int32`**  
Vectored write.

### Readiness

**`TTY.wait_readable(fd : Int32, timeout_ms : Int32 = -1) : Bool`**  
Wait until readable, HUP, or error.

**`TTY.wait_writable(fd : Int32, timeout_ms : Int32 = -1) : Bool`**  
Wait until writable, HUP, or error.

**`TTY.wait_priority(fd : Int32, timeout_ms : Int32 = -1) : Bool`**  
Wait for priority data, HUP, or error.

**`TTY.wait_io(fd : Int32, events : IOEvent, timeout_ms : Int32 = -1) : Bool`**  
Wait for an explicit event mask.

**`TTY.poll(fds : Array(PollFd), timeout_ms : Int32 = -1) : Int32`**  
Poll multiple fds.

**`TTY.poll(fds : Slice(PollFd), timeout_ms : Int32 = -1) : Int32`**  
Poll a slice of fds.

**`TTY::IOEvent`**  
`Readable`, `Priority`, `Writable`, `Error`, `HangUp`, `Invalid`.

**`TTY::PollFd.watch(fd, events) : PollFd`**  
Create a poll watch.

**`PollFd#fd`, `#events`, `#revents`**  
Poll fd, requested events, and returned events.

**`PollFd#readable?`, `#priority?`, `#writable?`**  
Returned readiness checks.

**`PollFd#error?`, `#hangup?`, `#invalid?`**  
Returned error-state checks.

### Poller

**`TTY::Poller.new(backend = PollerBackendKind::Auto)`**  
Create a poller.

**`TTY::Poller.poll : Poller`**  
Create a poll-backend poller.

**`Poller#backend : PollerBackendKind`**  
Selected backend.

**`Poller#watch(fd, events : IOEvent) : Nil`**  
Add or update an fd watch.

**`Poller#unwatch(fd) : Nil`**  
Remove an fd watch.

**`Poller#wait(timeout_ms = -1) : Array(PollerEvent)`**  
Wait for events.

**`Poller#close : Nil`**  
Close the poller.

**`Poller#closed? : Bool`**  
Whether the poller is closed.

**`TTY::PollerBackendKind`**  
`Auto`, `Poll`, `Epoll`, `Kqueue`.

**`TTY::PollerEvent#fd`, `#events`**  
Event fd and flags.

**`PollerEvent#readable?`, `#priority?`, `#writable?`**  
Event readiness checks.

**`PollerEvent#error?`, `#hangup?`, `#invalid?`**  
Event error-state checks.

### Termios types

**`TTY::SetAction`**  
`Now`, `Drain`, `Flush`; maps to `TCSETS`, `TCSETSW`, `TCSETSF`.

**`TTY::FlushQueue`**  
`Input`, `Output`, `Both`.

**`TTY::InputFlag`**  
Platform termios input flags.

**`TTY::OutputFlag`**  
Platform termios output flags.

**`TTY::ControlFlag`**  
Platform termios control flags.

**`TTY::LocalFlag`**  
Platform termios local flags.

**`TTY::ControlChar`**  
Platform control-character indexes such as `Min`, `Time`, `Intr`, `Quit`, `Start`, `Stop`.

**`TTY::Baud`**  
Standard baud enum; Linux also has `BOther` for custom speeds.

**`TTY::Termios.get(fd) : Termios`**  
Read attributes.

**`Termios#set(fd, action = SetAction::Now) : Nil`**  
Write attributes.

**`Termios#input`, `#output`, `#control`, `#local`**  
Get flag sets.

**`Termios#input=`, `#output=`, `#control=`, `#local=`**  
Set flag sets.

**`Termios#line`, `#line=`**  
Line discipline; no-op on Darwin.

**`Termios#[cc]`, `#[]=(cc, value)`**  
Access control characters.

**`Termios#baud`, `#baud=`**  
Standard baud get/set.

**`Termios#custom_baud?`**  
True when Linux `BOther` is active; always false on Darwin.

**`Termios#read_timeout`, `#read_timeout=`**  
`Time::Span?` mapped to `MIN`/`TIME`; `nil` whenever `TIME` is zero (blocking read, any `MIN`).

**`Termios#make_raw`, `#make_cbreak`**  
Mutate the struct to raw/cbreak settings.

**`Termios#to_s(io)`**  
Human-readable termios summary.

Linux-only custom baud:

**`TTY::Termios2.get(fd) : Termios2`**  
Read `termios2`.

**`TTY::Termios2.from(termios : Termios) : Termios2`**  
Copy a `Termios` into `Termios2`.

**`Termios2#set(fd, action = SetAction::Now) : Nil`**  
Write `termios2`.

**`Termios2#input_speed`, `#output_speed`**  
Raw speed fields.

**`Termios2#custom_baud=(rate : UInt32)`**  
Set `BOther` with a custom baud rate.

**`Termios2#custom_baud?`**  
Whether `BOther` is active.

### Window size

**`TTY::Winsize.new(rows = 0, cols = 0, xpixel = 0, ypixel = 0)`**  
Create a size struct.

**`Winsize#rows`, `#cols`, `#xpixel`, `#ypixel`**  
Mutable properties.

**`TTY::Winsize.get(fd) : Winsize`**  
Read size.

**`TTY::Winsize.current(fd = 0) : Winsize?`**  
Read size, or `nil` when the fd is not a terminal.

**`TTY::Winsize.propagate(from_fd, to_fd) : Nil`**  
Apply the source size immediately and mirror later `SIGWINCH` resizes.

**`Winsize#set(fd) : Nil`**  
Write size.

### Control and session

**`TTY.pending_input(fd) : Int32`**  
Bytes available to read.

**`TTY.pending_output(fd) : Int32`**  
Bytes still queued for output.

**`TTY.inject(fd, byte : UInt8) : Nil`**  
Inject one input byte (`TIOCSTI`).

**`TTY.send_break(fd) : Nil`**  
Assert break.

**`TTY.clear_break(fd) : Nil`**  
Clear break.

**`TTY.drain(fd) : Nil`**  
Wait for output to drain.

**`TTY.flow_control(fd, action : FlowAction) : Nil`**  
Software flow control. Linux-only.

**`TTY.modem_status(fd) : ModemLine`**  
Read modem lines.

**`TTY.set_modem_status(fd, lines : ModemLine) : Nil`**  
Write modem lines.

**`TTY.set_modem_lines(fd, lines : ModemLine) : Nil`**  
Set selected modem lines. Linux-only.

**`TTY.clear_modem_lines(fd, lines : ModemLine) : Nil`**  
Clear selected modem lines. Linux-only.

**`TTY.wait_modem(fd, lines : ModemLine) : Nil`**  
Wait for modem-line changes. Linux-only.

**`TTY.serial_icount(fd) : SerialICount`**  
Read serial interrupt counters. Linux-only.

**`TTY.output_empty?(fd) : Bool`**  
Read Linux serial line-status output state. Linux-only.

**`TTY::ModemLine`**  
Flags: `LE`, `DTR`, `RTS`, `ST`, `SR`, `CTS`, `CD`, `RI`, `DSR`.

**`TTY::FlowAction`**  
`SuspendOutput`, `ResumeOutput`, `SuspendInput`, `ResumeInput`.

**`TTY::SerialICount`**  
Serial interrupt counter fields.

**`TTY::Session.start : Int32`**  
Call `setsid` in the current process.

**`TTY::Session.leader : Int32`**  
Deprecated alias for `Session.start`.

**`TTY::Session.make_controlling(fd) : Nil`**  
Make fd the controlling terminal (`TIOCSCTTY`).

**`TTY::Session.detach(fd) : Nil`**  
Relinquish the controlling terminal (`TIOCNOTTY`).

**`TTY::Session.id(fd) : Int32`**    
Read the terminal session ID (`TIOCGSID`).

**`TTY::Session.foreground_pgrp(fd) : Int32`**  
Read foreground process group (`TIOCGPGRP`).

**`TTY::Session.set_foreground_pgrp(fd, pgrp) : Nil`**  
Set foreground process group (`TIOCSPGRP`).

**`TTY::Session.process_group(pid = 0) : Int32`**  
Read a process group. Linux-only.

**`TTY::Session.set_process_group(pid, pgrp) : Nil`**  
Set a process group. Linux-only.

**`TTY::Session.signal_process_group(pgrp, signal) : Nil`**  
Signal a process group.

**`TTY::Session.line_discipline(fd) : Int32`**  
Read the line discipline (`TIOCGETD`).

**`TTY::Session.set_line_discipline(fd, discipline) : Nil`**  
Set the line discipline (`TIOCSETD`).

**`TTY::Session.exclusive(fd, enable = true) : Nil`**  
Toggle exclusive terminal mode (`TIOCEXCL`/`TIOCNXCL`).

**`TTY::Session.exclusive?(fd) : Bool`**  
Query exclusive mode. Linux-only.

### PTY

**`TTY::PTY.open : PTY`**  
Allocate a PTY pair.

**`PTY.spawn(command, args = [] of String, *, env = SpawnOptions.default_env, winsize = nil, working_dir = nil, close_fds = true) : PTY::Process`**  
Spawn a child on a new PTY; the default environment inherits `ENV` plus a `TERM` fallback.

**`PTY.spawn(command, args, options : SpawnOptions) : PTY::Process`**  
Spawn with a `SpawnOptions` value.

**`TTY::PTY.wait(pid : Int32) : ChildStatus`**  
Blocking wait by pid.

**`PTY#master_fd`, `#slave_fd`, `#slave_name`**  
Raw fds and slave path.

**`PTY#closed? : Bool`**  
Whether master is closed.

**`PTY#eof_on_error : Bool`**  
Property, default `true`: master reads after child exit report end-of-stream (`0`/`EndOfStream`) instead of raising `EIO`. Set to `false` to keep raising.

**`PTY#close_slave : Nil`**  
Close only the slave fd.

**`PTY#close : Nil`**  
Idempotently close slave and master; closes the evented `PTY::IO` and any `master_io`/`slave_io` adapters first.

**`PTY#locked? : Bool`**  
Query PTY slave lock state. Linux-only.

**`PTY#packet_mode=(enabled : Bool)`**  
Enable or disable packet mode.

**`PTY#packet_mode? : Bool`**  
Query packet mode. Linux-only.

**`PTY#read_packet(buffer) : Packet`**  
Read a packet-mode data or control packet.

**`PTY#master_io`, `#slave_io`**  
`IO::FileDescriptor` adapters with `close_on_finalize` disabled; closed by `PTY#close`.

**`PTY#io : PTY::IO`**  
Fiber-aware `IO` over the master, integrated with the Crystal event loop; one per PTY. See *Evented I/O*.

**`PTY::IO.new(pty, eof_on_error = nil)`**  
Create the evented wrapper directly; `eof_on_error` defaults to the PTY's setting.

**`PTY#read_master(buffer)`, `#write_master(data)`**  
Master-side I/O; reads return `0` on child exit unless `eof_on_error` is disabled.

**`PTY#read_master_v(buffers)`, `#write_master_v(buffers)`**  
Vectored master-side I/O.

**`PTY#read_slave(buffer)`, `#write_slave(data)`**  
Slave-side I/O.

**`PTY#wait_readable(timeout_ms = -1)`, `#wait_writable(timeout_ms = -1)`**  
PTY readiness.

**`PTY#wait_priority(timeout_ms = -1)`**  
Wait for priority data.

**`PTY#termios`, `#termios=`**  
Terminal attributes on the effective fd.

**`PTY#winsize`, `#winsize=`**  
Window size.

On Linux, `PTY.open` uses `TIOCGPTPEER` when available and falls back to opening the `/dev/pts/N` pathname.

### Spawn options and packets

**`TTY::SpawnOptions.new(env = SpawnOptions.default_env, winsize = nil, working_dir = nil, close_fds = true)`**  
PTY process options.

**`TTY::SpawnOptions.default_env : Hash(String, String)`**  
`ENV` plus a `TERM` fallback of `xterm-256color` when unset.

**`SpawnOptions#env`**  
Child environment.

**`SpawnOptions#winsize`**  
Optional initial PTY size.

**`SpawnOptions#working_dir`**  
Optional child working directory.

**`SpawnOptions#close_fds`**  
Close unrelated fds before exec on Linux.

**`TTY::Packet#kind`**  
`Data`, `Control`, or `EndOfStream`.

**`TTY::Packet#events`**  
Control event flags.

**`TTY::Packet#size`**  
Data byte count.

**`Packet#data?`, `#control?`, `#end_of_stream?`**  
Packet kind checks.

**`TTY::PacketEvent`**  
`Data`, `FlushRead`, `FlushWrite`, `Stop`, `Start`, `NoStop`, `DoStop`.

### PTY process

**`PTY::Process#pid : Int32`**  
Child pid.

**`PTY::Process#pty : PTY`**  
Owned PTY.

**`PTY::Process#wait : ChildStatus`**  
Blocking wait; caches terminal status. Recovers the status when the runtime's `SIGCHLD` handling reaped the child first (see *Concurrency*).

**`PTY::Process#wait(timeout_ms : Int32) : ChildStatus?`**  
Timed wait; `nil` on timeout. Uses the pidfd when one is available.

**`PTY::Process#wait_event : ChildEvent`**  
Blocking Linux `waitid` event; composes with `wait` in either order and recovers externally reaped children the same way. Linux-only.

**`PTY::Process#wait_event(timeout_ms : Int32) : ChildEvent?`**  
Timed Linux `waitid` event. Linux-only.

**`PTY::Process#status : ChildStatus?`**  
Cached terminal status, if already known.

**`PTY::Process#last_event : ChildEvent?`**  
Most recent child event.

**`PTY::Process#exited? : Bool`**  
Whether a terminal status has been observed.

**`PTY::Process#pidfd? : Int32?`**  
Existing Linux pidfd, if available. Linux-only.

**`PTY::Process#pidfd : Int32`**  
Get or open a Linux pidfd. Linux-only.

**`PTY::Process#poll_exit(timeout_ms = -1) : Bool`**  
Poll a Linux pidfd for exit. Linux-only.

**`PTY::Process#signal(signal : Int32) : Nil`**  
Send a raw signal number.

**`PTY::Process#terminate : Nil`**  
Send `SIGTERM`.

**`PTY::Process#kill : Nil`**  
Send `SIGKILL`.

**`PTY::Process#close : Nil`**  
Close the pidfd and owned PTY.

### Child status and child events

**`ChildStatus#exited? : Bool`**  
Normal exit.

**`ChildStatus#exit_status : Int32`**  
Exit code when `exited?`.

**`ChildStatus#signaled? : Bool`**  
Terminated by a signal.

**`ChildStatus#term_signal : Int32`**  
Terminating signal number.

**`ChildStatus#stopped? : Bool`**  
Stopped by job control.

**`ChildStatus#core_dumped? : Bool`**  
Terminated with a core dump.

**`ChildStatus#success? : Bool`**  
Exited with status `0`.

**`ChildEvent#kind`**  
`ChildEventKind` value.

**`ChildEvent#pid`**  
Child pid.

**`ChildEvent#uid`**  
Child user ID.

**`ChildEvent#status`**  
Exit code or signal number.

**`ChildEvent#exited?`**  
Normal exit.

**`ChildEvent#exit_status`**  
Exit code.

**`ChildEvent#signaled?`**  
Killed or dumped.

**`ChildEvent#term_signal`**  
Terminating signal.

**`ChildEvent#stopped?`**  
Stopped.

**`ChildEvent#stop_signal`**  
Stop signal.

**`ChildEvent#continued?`**  
Continued.

**`ChildEvent#trapped?`**  
Trapped.

**`ChildEvent#core_dumped?`**  
Core dumped.

**`ChildEvent#terminal?`**  
Exited or signaled.

**`ChildEvent#success?`**  
Exited with status `0`.

**`ChildEvent#wait_status`**  
Traditional wait status.

`TTY::ChildEventKind` values are `None`, `Exited`, `Killed`, `Dumped`, `Trapped`, `Stopped`, and `Continued`.

**`TTY::ChildEvent.from_wait_status(pid, status) : ChildEvent`**  
Reconstruct an event from a traditional wait status word.

### Errors

**`TTY::Error`**  
Base shard error.

**`TTY::PTY::Error`**  
PTY-specific error.

**`TTY::PTY::ExecError`**  
Child exec failure.

**`ExecError#command`, `#attempts`**  
Command and attempted paths.

**`ExecError#errno`, `#errno_name`**  
Final exec errno and symbolic name.

**`TTY::Syscall::Error`**  
Syscall failure with context.

**`Syscall::Error#errno`, `#errno_name`**  
Numeric errno and short name.

**`Syscall::Error#operation`, `#fd`, `#path`, `#request`**  
Context fields; optional fields are `nil` when absent.

### Low-level syscall module

`TTY::Syscall` is the escape hatch used by the public APIs. It is public, but most callers should prefer the higher-level wrappers.

**`Syscall.raw(nr, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0)`**  
Direct inline-assembly syscall.

**`Syscall.check(ret, operation = "syscall", fd = nil, path = nil, request = nil)`**  
Convert negative returns to `Syscall::Error`.

**`Syscall.read(fd, buffer, count)`, `write(fd, data)`, `close(fd)`**  
Basic fd operations.

**`Syscall.readv(fd, iovecs, count)`, `writev(fd, iovecs, count)`**  
Vectored fd operations.

**`Syscall.fcntl(fd, command, argument = 0)`, `fstat(fd)`**  
Fd flags and Linux stat.

**`Syscall.ioctl(fd, request, arg)`, `ioctl_result(fd, request, arg)`**  
Pointer or integer ioctl.

**`Syscall.openat(path, flags)`**  
Open relative to `AT_FDCWD`.

**`Syscall.pipe2(fds, flags)`, `dup2`, `dup3`, `chdir`, `close_range`**  
Fd and directory primitives.

**`Syscall.close_fds_from(first, except)`**  
Close all fds from `first` up, keeping `except`; falls back to a `/proc/self/fd` walk when `close_range` is unavailable. Allocation-free and safe to run after `fork`. Linux-only.

**`Syscall.close_fds_via_procfs(first, last, except)`**  
Close fds by walking `/proc/self/fd` directly. Linux-only.

**`Syscall.splice(fd_in, offset_in, fd_out, offset_out, count, flags = 0)`, `tee(fd_in, fd_out, count, flags = 0)`, `copy_file_range(fd_in, offset_in, fd_out, offset_out, count, flags = 0)`**  
Zero-copy transfer primitives; offsets are optional and `nil` uses the current file position. Linux-only.

**`Syscall.fork`, `execve`, `setsid`, `setpgid`, `getpgid`, `kill`, `killpg`**  
Process primitives.

**`Syscall.wait4(pid, options = 0)`, `waitid(id_type, id, options)`**  
Child waiting primitives.

**`Syscall.pidfd_open(pid, flags = 0)`, `pidfd_send_signal(pidfd, signal, flags = 0)`**  
Linux pidfd primitives.

**`Syscall.poll(fds, nfds, timeout_ms)`, `sleep_ms(timeout_ms)`**  
Raw poll and poll-based sleep.

**`Syscall.socketpair(domain, type, protocol, fds)`**  
Create a connected fd pair.

**`Syscall.epoll_create1`, `epoll_ctl`, `epoll_wait`**  
Linux epoll primitives.

**`Syscall.kqueue`, `kevent`**  
Darwin kqueue primitives.

**`Syscall.reset_child_signal_state`**  
Reset all catchable handlers to default (including Linux real-time signals, skipping the NPTL-reserved 32/33) and clear the signal mask.

**`Syscall.exit_group(code)`**  
Exit all threads.

Common constants include `WNOHANG`, `WEXITED`, `WSTOPPED`, `WCONTINUED`, `WNOWAIT`, `EINTR`, `EIO`, `EBADF`, `ECHILD`, `EAGAIN`, `ENOSYS`, `AF_UNIX`, `SOCK_STREAM`, `SIGKILL`, `SIGTERM`, `SIGCONT`, and `SIGSTOP`. Errno constants always use the host platform's numbering (`EAGAIN` and `ENOSYS` differ between Linux and Darwin), and `SPLICE_F_MOVE`/`SPLICE_F_NONBLOCK`/`SPLICE_F_MORE`/`SPLICE_F_GIFT` are available on Linux.

## Examples

Run every example directly:

```sh
make examples
```

The target runs every `examples/*.cr` file with `crystal run`:

- `termios`
- `readiness`
- `pty_process`
- `winsize`
- `control`
- `session`
- `errors`
- `fd`
- `packet`
- `poller`
- `spawn_error`
- `child_events`
- `configure`
- `with_terminal`
- `spawn_dsl`

## Development

```sh
make spec
make examples
make bench
make clean
```

`make spec` runs the spec suite. `make examples` runs all examples. `make bench` runs the `benchmarks/` programs with `--release` (raw syscall round-trips, PTY throughput with and without vectored I/O, poller latency across idle fds, and macro-layer overhead against the imperative equivalents). `make clean` removes `.build` when build artifacts exist.

## Notes

- The core APIs use raw values: `Int32` fds, integer millisecond timeouts, and integer signal numbers.
- Some convenience APIs still use Crystal stdlib types, including `IO::FileDescriptor`, `Time::Span` for termios read timeouts, `ENV` as the default spawn environment, and `Signal::WINCH` for resize callbacks.
- `TTY::PTY::IO` wraps the master in the Crystal event loop; constructing it switches the master fd to nonblocking mode, and only one may exist per PTY.
- `TTY::PTY.spawn` resets all catchable child signal handlers to default and clears the signal mask before `execve`.
- `TTY::PTY.spawn` uses a close-on-exec error pipe so exec failures are reported to the parent instead of appearing only as exit status `127`.
- `TTY::Session.start` calls `setsid`; use it only in a process that is not already a process-group leader.
- Kernel ABI structs use explicit external layouts for ioctl and syscall data.
- Linux-only features include `TIOCGPTPEER`, `termios2`, `close_range` and its `/proc/self/fd` fallback, `splice`/`tee`/`copy_file_range`, `waitid` child events, pidfds, `epoll`, serial counters, modem waiting, and several advanced ioctls.

## License

MIT