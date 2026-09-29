# tty

`tty` is a Crystal shard for Unix terminals and pseudo-terminals. It provides termios control, window size handling, terminal/session ioctls, readiness waits, PTY allocation, packet mode, process lifecycle management, pidfds, and event polling on top of a raw-syscall core.

The syscall trampoline uses Crystal inline assembly. The shard has no C bindings, no external assembly object, no postinstall step, and no separate C compiler requirement.

## Features

- Inline Crystal syscall trampoline with zero-through-six-argument calls
- Termios get/set with input, output, control, and local flag enums
- Raw and cbreak helpers with scoped restoration
- Standard baud rates and Linux custom baud rates through `termios2`/`BOTHER`
- File descriptor flags, nonblocking mode, close-on-exec, pipes, `dup3`, `fstat`, vectored I/O, and `close_range`
- Single-fd and multi-fd readiness waits using integer millisecond timeouts
- Poller abstraction with `poll`, Linux `epoll`, and Darwin `kqueue` backends
- Window size get/set and resize notification
- Input/output queue inspection, drain, break control, software flow control, modem lines, serial counters, and byte injection
- Session, controlling-terminal, foreground process-group, process-group, line-discipline, and exclusive-mode helpers
- PTY open/close, Linux `TIOCGPTPEER`, master/slave fd access, and optional `IO::FileDescriptor` adapters
- PTY packet mode with data and control packet parsing
- PTY child spawning with exec error reporting, working-directory support, fd cleanup, signal-state reset, `wait`, timed `wait`, `terminate`, and `kill`
- Linux `waitid` child events for exit, signal, core dump, stop, continue, and trap states
- Linux pidfd creation, exit polling, and pidfd-based signals
- Structured syscall errors with `errno`, `errno_name`, `operation`, `fd`, `path`, and `request`

## Requirements

- Crystal `>= 1.10.0`
- x86-64
- Linux for the complete feature set
- macOS for the compile-gated best-effort backend

Linux is the primary target and receives the complete runtime coverage. The macOS backend includes direct-syscall and `kqueue` paths, but direct kernel syscall compatibility on macOS is best-effort. Linux-only APIs are unavailable or raise `TTY::Error` on Darwin.

The shard itself does not require a C compiler or a postinstall build.

## Installation

Use a local path dependency while developing:

```yaml
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

`process.wait` blocks until exit. `process.wait(timeout_ms)` returns `TTY::ChildStatus?` and returns `nil` on timeout. `process.status` returns the cached terminal status after a successful wait.

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

Resize notifications for a terminal fd:

```crystal
TTY.on_resize(0) do |size|
  puts "#{size.cols}x#{size.rows}"
end
```

## Public API reference

### Top-level `TTY`

| API                                                        | Description                                      |
|------------------------------------------------------------|--------------------------------------------------|
| `TTY.termios(fd : Int32) : Termios`                        | Read terminal attributes from an fd.             |
| `TTY.termios(io : IO::FileDescriptor) : Termios`           | Read terminal attributes from an IO.             |
| `TTY.winsize(fd : Int32) : Winsize`                        | Read window size from an fd.                     |
| `TTY.winsize(io : IO::FileDescriptor) : Winsize`           | Read window size from an IO.                     |
| `TTY.nonblocking?(fd) : Bool`                              | Read `O_NONBLOCK`.                               |
| `TTY.set_nonblocking(fd, enabled = true) : Nil`            | Set or clear `O_NONBLOCK`.                       |
| `TTY.cloexec?(fd) : Bool`                                  | Read `FD_CLOEXEC`.                               |
| `TTY.set_cloexec(fd, enabled = true) : Nil`                | Set or clear `FD_CLOEXEC`.                       |
| `TTY.raw(fd, action = SetAction::Now) { ... }`             | Enable raw mode for the block, then restore.     |
| `TTY.raw(io, action = SetAction::Now) { ... }`             | IO overload of `raw`.                            |
| `TTY.cbreak(fd, action = SetAction::Now) { ... }`          | Enable cbreak mode for the block, then restore.  |
| `TTY.cbreak(io, action = SetAction::Now) { ... }`          | IO overload of `cbreak`.                         |
| `TTY.flush(fd, queue = FlushQueue::Both) : Nil`            | Flush input/output queues.                       |
| `TTY.on_resize(fd) { |winsize| ... } : Nil`                | Trap `SIGWINCH` and yield the current size.      |

### File descriptors

| API                                                        | Description                                      |
|------------------------------------------------------------|--------------------------------------------------|
| `TTY::FD.status_flags(fd) : Int32`                         | Read file status flags.                          |
| `TTY::FD.descriptor_flags(fd) : Int32`                     | Read file descriptor flags.                      |
| `TTY::FD.nonblocking?(fd) : Bool`                          | Whether `O_NONBLOCK` is set.                     |
| `TTY::FD.set_nonblocking(fd, enabled = true) : Nil`        | Set or clear `O_NONBLOCK`.                       |
| `TTY::FD.cloexec?(fd) : Bool`                              | Whether `FD_CLOEXEC` is set.                     |
| `TTY::FD.set_cloexec(fd, enabled = true) : Nil`            | Set or clear `FD_CLOEXEC`.                       |
| `TTY::FD.pipe(cloexec = true) : Tuple(Int32, Int32)`       | Create a pipe.                                   |
| `TTY::FD.dup3(old_fd, new_fd, cloexec = true) : Nil`       | Duplicate to an exact fd. Linux-only.            |
| `TTY::FD.duplicate_cloexec(fd, minimum_fd = 0) : Int32`    | Duplicate with close-on-exec.                    |
| `TTY::FD.close_range(first, last = Int32::MAX) : Nil`      | Close a range of fds. Linux-only.                |
| `TTY::FD.stat(fd)`                                         | Read Linux stat metadata. Linux-only.            |
| `TTY::FD.mode(fd) : UInt32`                                | Read the file mode. Linux-only.                  |
| `TTY::FD.character_device?(fd) : Bool`                     | Whether fd is a character device. Linux-only.    |
| `TTY::FD.readv(fd, buffers) : Int32`                       | Vectored read.                                   |
| `TTY::FD.writev(fd, buffers) : Int32`                      | Vectored write.                                  |

### Readiness

| API                                                                            | Description                                           |
|--------------------------------------------------------------------------------|-------------------------------------------------------|
| `TTY.wait_readable(fd : Int32, timeout_ms : Int32 = -1) : Bool`                | Wait until readable, HUP, or error.                   |
| `TTY.wait_writable(fd : Int32, timeout_ms : Int32 = -1) : Bool`                | Wait until writable, HUP, or error.                   |
| `TTY.wait_priority(fd : Int32, timeout_ms : Int32 = -1) : Bool`                | Wait for priority data, HUP, or error.                |
| `TTY.wait_io(fd : Int32, events : IOEvent, timeout_ms : Int32 = -1) : Bool`    | Wait for an explicit event mask.                      |
| `TTY.poll(fds : Array(PollFd), timeout_ms : Int32 = -1) : Int32`               | Poll multiple fds.                                    |
| `TTY.poll(fds : Slice(PollFd), timeout_ms : Int32 = -1) : Int32`               | Poll a slice of fds.                                  |
| `TTY::IOEvent`                                                                 | `Readable`, `Priority`, `Writable`, `Error`, `HangUp`, `Invalid`. |
| `TTY::PollFd.watch(fd, events) : PollFd`                                       | Create a poll watch.                                  |
| `PollFd#fd`, `#events`, `#revents`                                             | Poll fd, requested events, and returned events.       |
| `PollFd#readable?`, `#priority?`, `#writable?`                                 | Returned readiness checks.                            |
| `PollFd#error?`, `#hangup?`, `#invalid?`                                       | Returned error-state checks.                          |

### Poller

| API                                                        | Description                                      |
|------------------------------------------------------------|--------------------------------------------------|
| `TTY::Poller.new(backend = PollerBackendKind::Auto)`       | Create a poller.                                 |
| `TTY::Poller.poll : Poller`                                | Create a poll-backend poller.                    |
| `Poller#backend : PollerBackendKind`                       | Selected backend.                                |
| `Poller#watch(fd, events : IOEvent) : Nil`                 | Add or update an fd watch.                       |
| `Poller#unwatch(fd) : Nil`                                 | Remove an fd watch.                              |
| `Poller#wait(timeout_ms = -1) : Array(PollerEvent)`        | Wait for events.                                 |
| `Poller#close : Nil`                                       | Close the poller.                                |
| `Poller#closed? : Bool`                                    | Whether the poller is closed.                    |
| `TTY::PollerBackendKind`                                   | `Auto`, `Poll`, `Epoll`, `Kqueue`.               |
| `TTY::PollerEvent#fd`, `#events`                           | Event fd and flags.                              |
| `PollerEvent#readable?`, `#priority?`, `#writable?`        | Event readiness checks.                          |
| `PollerEvent#error?`, `#hangup?`, `#invalid?`              | Event error-state checks.                        |

### Termios types

| Type/API                                             | Description                                                                                |
|------------------------------------------------------|--------------------------------------------------------------------------------------------|
| `TTY::SetAction`                                     | `Now`, `Drain`, `Flush`; maps to `TCSETS`, `TCSETSW`, `TCSETSF`.                           |
| `TTY::FlushQueue`                                    | `Input`, `Output`, `Both`.                                                                 |
| `TTY::InputFlag`                                     | Platform termios input flags.                                                              |
| `TTY::OutputFlag`                                    | Platform termios output flags.                                                             |
| `TTY::ControlFlag`                                   | Platform termios control flags.                                                            |
| `TTY::LocalFlag`                                     | Platform termios local flags.                                                              |
| `TTY::ControlChar`                                   | Platform control-character indexes such as `Min`, `Time`, `Intr`, `Quit`, `Start`, `Stop`. |
| `TTY::Baud`                                          | Standard baud enum; Linux also has `BOther` for custom speeds.                             |
| `TTY::Termios.get(fd) : Termios`                     | Read attributes.                                                                           |
| `Termios#set(fd, action = SetAction::Now) : Nil`     | Write attributes.                                                                          |
| `Termios#input`, `#output`, `#control`, `#local`     | Get flag sets.                                                                             |
| `Termios#input=`, `#output=`, `#control=`, `#local=` | Set flag sets.                                                                             |
| `Termios#line`, `#line=`                             | Line discipline; no-op on Darwin.                                                          |
| `Termios#[cc]`, `#[]=(cc, value)`                    | Access control characters.                                                                 |
| `Termios#baud`, `#baud=`                             | Standard baud get/set.                                                                     |
| `Termios#custom_baud?`                               | True when Linux `BOther` is active; always false on Darwin.                                |
| `Termios#read_timeout`, `#read_timeout=`             | `Time::Span?` mapped to `MIN`/`TIME`.                                                      |
| `Termios#make_raw`, `#make_cbreak`                   | Mutate the struct to raw/cbreak settings.                                                  |
| `Termios#to_s(io)`                                   | Human-readable termios summary.                                                            |

Linux-only custom baud:

| API                                                | Description                           |
|----------------------------------------------------|---------------------------------------|
| `TTY::Termios2.get(fd) : Termios2`                 | Read `termios2`.                      |
| `TTY::Termios2.from(termios : Termios) : Termios2` | Copy a `Termios` into `Termios2`.     |
| `Termios2#set(fd, action = SetAction::Now) : Nil`  | Write `termios2`.                     |
| `Termios2#input_speed`, `#output_speed`            | Raw speed fields.                     |
| `Termios2#custom_baud=(rate : UInt32)`             | Set `BOther` with a custom baud rate. |
| `Termios2#custom_baud?`                            | Whether `BOther` is active.           |

### Window size

| API                                                            | Description           |
|----------------------------------------------------------------|-----------------------|
| `TTY::Winsize.new(rows = 0, cols = 0, xpixel = 0, ypixel = 0)` | Create a size struct. |
| `Winsize#rows`, `#cols`, `#xpixel`, `#ypixel`                  | Mutable properties.   |
| `TTY::Winsize.get(fd) : Winsize`                               | Read size.            |
| `Winsize#set(fd) : Nil`                                        | Write size.           |

### Control and session

| API                                                        | Description                                                      |
|------------------------------------------------------------|------------------------------------------------------------------|
| `TTY.pending_input(fd) : Int32`                            | Bytes available to read.                                         |
| `TTY.pending_output(fd) : Int32`                           | Bytes still queued for output.                                   |
| `TTY.inject(fd, byte : UInt8) : Nil`                       | Inject one input byte (`TIOCSTI`).                               |
| `TTY.send_break(fd) : Nil`                                 | Assert break.                                                    |
| `TTY.clear_break(fd) : Nil`                                | Clear break.                                                     |
| `TTY.drain(fd) : Nil`                                      | Wait for output to drain.                                        |
| `TTY.flow_control(fd, action : FlowAction) : Nil`          | Software flow control. Linux-only.                               |
| `TTY.modem_status(fd) : ModemLine`                         | Read modem lines.                                                |
| `TTY.set_modem_status(fd, lines : ModemLine) : Nil`        | Write modem lines.                                               |
| `TTY.set_modem_lines(fd, lines : ModemLine) : Nil`         | Set selected modem lines. Linux-only.                            |
| `TTY.clear_modem_lines(fd, lines : ModemLine) : Nil`       | Clear selected modem lines. Linux-only.                          |
| `TTY.wait_modem(fd, lines : ModemLine) : Nil`              | Wait for modem-line changes. Linux-only.                         |
| `TTY.serial_icount(fd) : SerialICount`                     | Read serial interrupt counters. Linux-only.                      |
| `TTY.output_empty?(fd) : Bool`                             | Read Linux serial line-status output state. Linux-only.          |
| `TTY::ModemLine`                                           | Flags: `LE`, `DTR`, `RTS`, `ST`, `SR`, `CTS`, `CD`, `RI`, `DSR`. |
| `TTY::FlowAction`                                          | `SuspendOutput`, `ResumeOutput`, `SuspendInput`, `ResumeInput`.  |
| `TTY::SerialICount`                                        | Serial interrupt counter fields.                                 |
| `TTY::Session.leader : Int32`                              | Call `setsid` in the current process.                            |
| `TTY::Session.make_controlling(fd) : Nil`                  | Make fd the controlling terminal (`TIOCSCTTY`).                  |
| `TTY::Session.detach(fd) : Nil`                            | Relinquish the controlling terminal (`TIOCNOTTY`).               |
| `TTY::Session.id(fd) : Int32`                              | Read the terminal session ID (`TIOCGSID`).                       |
| `TTY::Session.foreground_pgrp(fd) : Int32`                 | Read foreground process group (`TIOCGPGRP`).                     |
| `TTY::Session.set_foreground_pgrp(fd, pgrp) : Nil`         | Set foreground process group (`TIOCSPGRP`).                      |
| `TTY::Session.process_group(pid = 0) : Int32`              | Read a process group. Linux-only.                                |
| `TTY::Session.set_process_group(pid, pgrp) : Nil`          | Set a process group. Linux-only.                                 |
| `TTY::Session.signal_process_group(pgrp, signal) : Nil`    | Signal a process group.                                          |
| `TTY::Session.line_discipline(fd) : Int32`                 | Read the line discipline (`TIOCGETD`).                           |
| `TTY::Session.set_line_discipline(fd, discipline) : Nil`   | Set the line discipline (`TIOCSETD`).                            |
| `TTY::Session.exclusive(fd, enable = true) : Nil`          | Toggle exclusive terminal mode (`TIOCEXCL`/`TIOCNXCL`).          |
| `TTY::Session.exclusive?(fd) : Bool`                       | Query exclusive mode. Linux-only.                                |

### PTY

| API                                                                                                                             | Description                                      |
|---------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------|
| `TTY::PTY.open : PTY`                                                                                                           | Allocate a PTY pair.                             |
| `PTY.spawn(command, args = [] of String, env = ENV.to_h, winsize = nil, working_dir = nil, close_fds = true) : PTY::Process`   | Spawn a child on a new PTY.                      |
| `PTY.spawn(command, args, options : SpawnOptions) : PTY::Process`                                                               | Spawn with a `SpawnOptions` value.               |
| `TTY::PTY.wait(pid : Int32) : ChildStatus`                                                                                      | Blocking wait by pid.                            |
| `PTY#master_fd`, `#slave_fd`, `#slave_name`                                                                                     | Raw fds and slave path.                          |
| `PTY#closed? : Bool`                                                                                                            | Whether master is closed.                        |
| `PTY#close_slave : Nil`                                                                                                         | Close only the slave fd.                         |
| `PTY#close : Nil`                                                                                                               | Idempotently close slave and master.             |
| `PTY#locked? : Bool`                                                                                                            | Query PTY slave lock state. Linux-only.          |
| `PTY#packet_mode=(enabled : Bool)`                                                                                              | Enable or disable packet mode.                   |
| `PTY#packet_mode? : Bool`                                                                                                       | Query packet mode. Linux-only.                   |
| `PTY#read_packet(buffer) : Packet`                                                                                              | Read a packet-mode data or control packet.       |
| `PTY#master_io`, `#slave_io`                                                                                                    | `IO::FileDescriptor` adapters.                   |
| `PTY#read_master(buffer)`, `#write_master(data)`                                                                                | Master-side I/O.                                 |
| `PTY#read_slave(buffer)`, `#write_slave(data)`                                                                                  | Slave-side I/O.                                  |
| `PTY#wait_readable(timeout_ms = -1)`, `#wait_writable(timeout_ms = -1)`                                                         | PTY readiness.                                   |
| `PTY#wait_priority(timeout_ms = -1)`                                                                                            | Wait for priority data.                          |
| `PTY#termios`, `#termios=`                                                                                                      | Terminal attributes on the effective fd.         |
| `PTY#winsize`, `#winsize=`                                                                                                      | Window size.                                     |

On Linux, `PTY.open` uses `TIOCGPTPEER` when available and falls back to opening the `/dev/pts/N` pathname.

### Spawn options and packets

| API                                                        | Description                                      |
|------------------------------------------------------------|--------------------------------------------------|
| `TTY::SpawnOptions.new(env = ENV.to_h, winsize = nil, working_dir = nil, close_fds = true)` | PTY process options. |
| `SpawnOptions#env`                                         | Child environment.                               |
| `SpawnOptions#winsize`                                     | Optional initial PTY size.                       |
| `SpawnOptions#working_dir`                                 | Optional child working directory.                |
| `SpawnOptions#close_fds`                                   | Close unrelated fds before exec on Linux.        |
| `TTY::Packet#kind`                                         | `Data`, `Control`, or `EndOfStream`.             |
| `TTY::Packet#events`                                       | Control event flags.                             |
| `TTY::Packet#size`                                         | Data byte count.                                 |
| `Packet#data?`, `#control?`, `#end_of_stream?`             | Packet kind checks.                              |
| `TTY::PacketEvent`                                         | `Data`, `FlushRead`, `FlushWrite`, `Stop`, `Start`, `NoStop`, `DoStop`. |

### PTY process

| API                                                        | Description                                      |
|------------------------------------------------------------|--------------------------------------------------|
| `PTY::Process#pid : Int32`                                 | Child pid.                                       |
| `PTY::Process#pty : PTY`                                   | Owned PTY.                                       |
| `PTY::Process#wait : ChildStatus`                          | Blocking wait; caches terminal status.           |
| `PTY::Process#wait(timeout_ms : Int32) : ChildStatus?`     | Timed wait; `nil` on timeout.                    |
| `PTY::Process#wait_event : ChildEvent`                     | Blocking Linux `waitid` event. Linux-only.       |
| `PTY::Process#wait_event(timeout_ms : Int32) : ChildEvent?` | Timed Linux `waitid` event. Linux-only.         |
| `PTY::Process#status : ChildStatus?`                       | Cached terminal status, if already known.        |
| `PTY::Process#last_event : ChildEvent?`                    | Most recent child event.                         |
| `PTY::Process#exited? : Bool`                              | Whether a terminal status has been observed.     |
| `PTY::Process#pidfd? : Int32?`                             | Existing Linux pidfd, if available. Linux-only.  |
| `PTY::Process#pidfd : Int32`                               | Get or open a Linux pidfd. Linux-only.           |
| `PTY::Process#poll_exit(timeout_ms = -1) : Bool`           | Poll a Linux pidfd for exit. Linux-only.         |
| `PTY::Process#signal(signal : Int32) : Nil`                | Send a raw signal number.                        |
| `PTY::Process#terminate : Nil`                             | Send `SIGTERM`.                                  |
| `PTY::Process#kill : Nil`                                  | Send `SIGKILL`.                                  |
| `PTY::Process#close : Nil`                                 | Close the pidfd and owned PTY.                   |

### Child status and child events

| API                               | Description                |
|-----------------------------------|----------------------------|
| `ChildStatus#exited? : Bool`      | Normal exit.               |
| `ChildStatus#exit_status : Int32` | Exit code when `exited?`.  |
| `ChildStatus#signaled? : Bool`    | Terminated by a signal.    |
| `ChildStatus#term_signal : Int32` | Terminating signal number. |
| `ChildStatus#stopped? : Bool`     | Stopped by job control.    |
| `ChildStatus#core_dumped? : Bool` | Terminated with a core dump. |
| `ChildStatus#success? : Bool`     | Exited with status `0`.    |

| API                               | Description                |
|-----------------------------------|----------------------------|
| `ChildEvent#kind`                 | `ChildEventKind` value.    |
| `ChildEvent#pid`                  | Child pid.                 |
| `ChildEvent#uid`                  | Child user ID.             |
| `ChildEvent#status`               | Exit code or signal number.|
| `ChildEvent#exited?`              | Normal exit.               |
| `ChildEvent#exit_status`          | Exit code.                 |
| `ChildEvent#signaled?`            | Killed or dumped.          |
| `ChildEvent#term_signal`          | Terminating signal.        |
| `ChildEvent#stopped?`             | Stopped.                   |
| `ChildEvent#stop_signal`          | Stop signal.               |
| `ChildEvent#continued?`           | Continued.                 |
| `ChildEvent#trapped?`             | Trapped.                   |
| `ChildEvent#core_dumped?`         | Core dumped.               |
| `ChildEvent#terminal?`            | Exited or signaled.        |
| `ChildEvent#success?`             | Exited with status `0`.    |
| `ChildEvent#wait_status`          | Traditional wait status.   |

`TTY::ChildEventKind` values are `None`, `Exited`, `Killed`, `Dumped`, `Trapped`, `Stopped`, and `Continued`.

### Errors

| API                                                        | Description                                            |
|------------------------------------------------------------|--------------------------------------------------------|
| `TTY::Error`                                               | Base shard error.                                      |
| `TTY::PTY::Error`                                          | PTY-specific error.                                    |
| `TTY::PTY::ExecError`                                      | Child exec failure.                                    |
| `ExecError#command`, `#attempts`                           | Command and attempted paths.                           |
| `ExecError#errno`, `#errno_name`                           | Final exec errno and symbolic name.                    |
| `TTY::Syscall::Error`                                      | Syscall failure with context.                          |
| `Syscall::Error#errno`, `#errno_name`                      | Numeric errno and short name.                          |
| `Syscall::Error#operation`, `#fd`, `#path`, `#request`     | Context fields; optional fields are `nil` when absent. |

### Low-level syscall module

`TTY::Syscall` is the escape hatch used by the public APIs. It is public, but most callers should prefer the higher-level wrappers.

| API                                                                                     | Description                                                    |
|-----------------------------------------------------------------------------------------|----------------------------------------------------------------|
| `Syscall.raw(nr, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0)`                      | Direct inline-assembly syscall.                                |
| `Syscall.check(ret, operation = "syscall", fd = nil, path = nil, request = nil)`       | Convert negative returns to `Syscall::Error`.                  |
| `Syscall.read(fd, buffer, count)`, `write(fd, data)`, `close(fd)`                      | Basic fd operations.                                           |
| `Syscall.readv(fd, iovecs, count)`, `writev(fd, iovecs, count)`                        | Vectored fd operations.                                        |
| `Syscall.fcntl(fd, command, argument = 0)`, `fstat(fd)`                                 | Fd flags and Linux stat.                                       |
| `Syscall.ioctl(fd, request, arg)`, `ioctl_result(fd, request, arg)`                    | Pointer or integer ioctl.                                      |
| `Syscall.openat(path, flags)`                                                           | Open relative to `AT_FDCWD`.                                   |
| `Syscall.pipe2(fds, flags)`, `dup2`, `dup3`, `chdir`, `close_range`                    | Fd and directory primitives.                                   |
| `Syscall.fork`, `execve`, `setsid`, `setpgid`, `getpgid`, `kill`, `killpg`             | Process primitives.                                            |
| `Syscall.wait4(pid, options = 0)`, `waitid(id_type, id, options)`                      | Child waiting primitives.                                      |
| `Syscall.pidfd_open(pid, flags = 0)`, `pidfd_send_signal(pidfd, signal, flags = 0)`    | Linux pidfd primitives.                                        |
| `Syscall.poll(fds, nfds, timeout_ms)`, `sleep_ms(timeout_ms)`                          | Raw poll and poll-based sleep.                                 |
| `Syscall.socketpair(domain, type, protocol, fds)`                                      | Create a connected fd pair.                                    |
| `Syscall.epoll_create1`, `epoll_ctl`, `epoll_wait`                                     | Linux epoll primitives.                                        |
| `Syscall.kqueue`, `kevent`                                                              | Darwin kqueue primitives.                                      |
| `Syscall.reset_child_signal_state`                                                     | Reset catchable handlers to default and clear the signal mask. |
| `Syscall.exit_group(code)`                                                              | Exit all threads.                                              |

Common constants include `WNOHANG`, `WEXITED`, `WSTOPPED`, `WCONTINUED`, `WNOWAIT`, `EINTR`, `EIO`, `EBADF`, `ECHILD`, `EAGAIN`, `ENOSYS`, `AF_UNIX`, `SOCK_STREAM`, `SIGKILL`, `SIGTERM`, `SIGCONT`, and `SIGSTOP`.

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

## Development

```sh
make spec
make examples
make clean
```

`make spec` runs the spec suite. `make examples` runs all examples. `make clean` removes `.build` when build artifacts exist.

## Notes

- The core APIs use raw values: `Int32` fds, integer millisecond timeouts, and integer signal numbers.
- Some convenience APIs still use Crystal stdlib types, including `IO::FileDescriptor`, `Time::Span` for termios read timeouts, `ENV` as the default spawn environment, and `Signal::WINCH` for resize callbacks.
- `TTY::PTY.spawn` resets catchable child signal handlers to default and clears the signal mask before `execve`.
- `TTY::PTY.spawn` uses a close-on-exec error pipe so exec failures are reported to the parent instead of appearing only as exit status `127`.
- `TTY::Session.leader` calls `setsid`; use it only in a process that is not already a process-group leader.
- Kernel ABI structs use explicit external layouts for ioctl and syscall data.
- Linux-only features include `TIOCGPTPEER`, `termios2`, `close_range`, `waitid` child events, pidfds, `epoll`, serial counters, modem waiting, and several advanced ioctls.

## License

MIT
