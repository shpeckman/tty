# tty

Terminals and pseudo-terminals for Crystal.

`tty` runs programs on a pseudo-terminal, scripts them, hands them to the user's terminal, and controls terminal modes, window sizes, sessions, and serial lines. The high-level API reads like Crystal's own `Process` and `IO`; underneath it sits a raw-syscall core with no libc wrappers, so every ioctl and flag is reachable when you need it.

```crystal
require "tty"

output, status = TTY::PTY.run("ls", ["--color=auto"])
```

## Contents

- [Installation](#installation)
- [A quick tour](#a-quick-tour)
- [Running programs](#running-programs)
- [Talking to a program](#talking-to-a-program)
- [Waiting, signals, and exit status](#waiting-signals-and-exit-status)
- [Controlling a terminal](#controlling-a-terminal)
- [Working with a PTY directly](#working-with-a-pty-directly)
- [Descriptors and readiness](#descriptors-and-readiness)
- [Sessions and serial lines](#sessions-and-serial-lines)
- [Conventions](#conventions)
- [Concurrency](#concurrency)
- [Platform support](#platform-support)
- [API reference](#api-reference)
- [Development](#development)

## Installation

Add the shard to `shard.yml`:

```yaml
dependencies:
  tty:
    github: shpeckman/tty
```

Run `shards install`, then `require "tty"`.

Requirements:

- Crystal 1.10 or newer
- x86-64
- Linux for the full feature set; macOS for the portable subset (see [Platform support](#platform-support))

## A quick tour

Capture what a program prints when it believes it is talking to a terminal:

```crystal
output, status = TTY::PTY.run("git", ["log", "--oneline", "-5"])
status.success?
```

Script an interactive program. The block form cleans up when the block ends:

```crystal
answer = TTY::PTY.spawn("python3") do |python|
  python.expect(">>> ", timeout: 2.seconds)
  python.send_line("print(40 + 2)")
  python.expect(/(\d+)\r\n/)[1]
end
```

Give a program to the user, exactly as if they had started it from their shell:

```crystal
status = TTY::PTY.spawn("vim", ["notes.txt"]).interact
```

Read a password without echoing it:

```crystal
password = TTY.with_terminal(STDIN, echo: false) { STDIN.gets }
```

## Running programs

### Capture: `PTY.run`

`PTY.run` starts the command on a fresh PTY, reads everything it writes until it exits, waits for it, and returns `{output, status}`.

```crystal
output, status = TTY::PTY.run("make", ["test"])
puts output
exit status.exit_code
```

The child sees a real terminal, so programs that only colorize or align columns on a TTY do so. Output newline translation is switched off on the PTY, so lines end in `\n` instead of the terminal's usual `\r\n`.

### Scoped: `PTY.spawn` with a block

With a block, `PTY.spawn` yields the running `PTY::Process` and returns the block's value. When the block ends, normally or through an exception, the PTY is closed, the child is reaped, and every descriptor is released.

```crystal
status = TTY::PTY.spawn("sh", ["-c", "read name; echo hello $name"]) do |process|
  process.send_line("crystal")
  process.gets
  process.wait
end
```

Closing the PTY hangs up the terminal, so a child that is still running receives `SIGHUP`. Call `process.wait` inside the block when the child should finish on its own terms; it also gives you the exit status.

### Unscoped: `PTY.spawn` without a block

Without a block you own the process: wait for it and close it yourself.

```crystal
process = TTY::PTY.spawn("tail", ["-f", "/var/log/syslog"])
5.times { puts process.gets }
process.terminate
process.wait
process.close
```

### Options

`PTY.spawn` and `PTY.run` take the same named options. They can also be bundled in a `TTY::SpawnOptions` value and passed as the third argument.

| Option | Default | Effect |
| --- | --- | --- |
| `env` | `nil` | Variables merged into the child's environment; a `nil` value removes that variable |
| `clear_env` | `false` | Start from an empty environment instead of the parent's |
| `shell` | `false` | Treat `command` as a shell command line run by `/bin/sh -c` |
| `winsize` | `nil` | Initial window size of the PTY |
| `working_dir` | `nil` | Directory the child starts in |
| `close_fds` | `true` | Close every inherited descriptor except stdio before exec (Linux) |

```crystal
TTY::PTY.spawn("make", env: {"CC" => "clang", "MAKEFLAGS" => nil}, working_dir: "/src")

options = TTY::SpawnOptions.new(winsize: TTY::Winsize.new(40_u16, 120_u16), clear_env: true)
TTY::PTY.spawn("top", [] of String, options)
```

An unknown option name is a compile error.

**Environment.** Without `clear_env`, the child inherits the parent's environment, and `TERM` defaults to `xterm-256color` when the parent has none, so full-screen programs work out of the box. `env` entries are applied on top. With `clear_env: true` the child gets only the `env` entries. The executable is found through the child's `PATH`, falling back to the parent's.

**Shell command lines.** With `shell: true`, `command` runs through `/bin/sh -c` and `args` become the shell's positional parameters. When there are `args` and the command line does not mention `"$@"`, ` "$@"` is appended so they reach the command.

```crystal
TTY::PTY.run("ls -l | wc -l", shell: true)
TTY::PTY.run("grep -c", ["TODO", "src/main.cr"], shell: true)
```

`SpawnOptions#environment` and `SpawnOptions#argv(command, args)` show exactly what the child will receive.

### When exec fails

If the program cannot be started, `PTY.spawn` and `PTY.run` raise `TTY::PTY::ExecError`, which carries the `errno` and every path that was tried. The failure is reported through a close-on-exec pipe, so it is never confused with a program that exits with status 127.

```crystal
begin
  TTY::PTY.spawn("no-such-program")
rescue ex : TTY::PTY::ExecError
  ex.errno_name
  ex.attempts
end
```

### The DSL form

`TTY.spawn` builds the same call from a block of declarations, checked at compile time:

```crystal
process = TTY.spawn("sh", ["-c", "ls"]) do
  env path: "/usr/bin:/bin", term: "xterm-256color"
  winsize rows: 24, cols: 80
  working_dir "/tmp"
  close_fds true
  clear_env false
  shell false
end
```

Named `env` keys are upcased (`env path: ...` sets `PATH`). Pass a hash literal for exact-case names: `env({"foo" => "bar"})`.

## Talking to a program

### A process is an IO

`TTY::PTY::Process` inherits from `IO`. Everything you know from `IO` works on it directly:

```crystal
process = TTY::PTY.spawn("cat")
process.puts "hello"
process.gets
process.each_line { |line| puts line }
```

Writes are unbuffered, so input reaches the child immediately; there is nothing to flush. Lines read from a terminal end in `\r\n`, which `gets` strips.

Reads and writes go through the event loop: a pending read suspends only the calling fiber, and other fibers keep running. When the child exits, reads report end of stream.

### Expect

`expect` reads until a `Regex` or a literal `String` matches, consumes everything up to the end of the match, and returns the `Regex::MatchData`. Whatever arrived after the match stays buffered for the next read.

```crystal
process.expect(/password: /i, timeout: 5.seconds)
process.send_line(secret)

match = process.expect(/logged in as (\w+)/)
match[1]
match.pre_match
```

- On timeout it raises `IO::TimeoutError`; if the program exits first it raises `IO::EOFError`. Either way, the bytes received so far remain readable.
- Matching works on raw terminal output, including bytes that are not valid UTF-8.
- `send_line(line)` writes the line followed by `\r`, the byte a terminal sends for Enter.

### Hand-over: `interact`

`interact` connects the program to a pair of streams, `STDIN` and `STDOUT` by default, and relays bytes in both directions until the program's output ends. It then waits for the program and returns its status.

```crystal
status = TTY::PTY.spawn("bash").interact
```

When the input is a terminal, it is put into raw mode for the duration, its window size is copied to the PTY immediately and again on every resize, and its settings are restored afterwards. Descriptor flags on the input are restored in every case. `interact` resets `SIGWINCH` to its default handling when it returns.

## Waiting, signals, and exit status

```crystal
process = TTY::PTY.spawn("sleep", ["30"])

if process.wait(100.milliseconds).nil?
  process.signal(Signal::TERM)
end

status = process.wait
status.signal_exit?
status.exit_signal
process.close
```

- `wait` blocks until the child exits and caches the result; later calls return the cached status, as does `status`.
- `wait(timeout)` returns `nil` on timeout. On Linux it sleeps on a pidfd, so it returns as soon as the child exits.
- `signal` takes a `Signal` or a signal number; `terminate` and `kill` send `SIGTERM` and `SIGKILL`.

Exit statuses answer to the same names as Crystal's `Process::Status` (`exit_code`, `normal_exit?`, `signal_exit?`, `exit_signal`, `success?`), alongside the traditional `exited?`, `exit_status`, `signaled?`, `term_signal`, `stopped?`, and `core_dumped?`.

### Stop and continue events (Linux)

`wait_event` reports every state change, including stops and continues, through `waitid`:

```crystal
process.signal(Signal::STOP)
process.wait_event.stopped?
process.signal(Signal::CONT)
process.wait_event.continued?
```

`wait_event` and `wait` can be mixed freely: whichever observes termination first records it, and the other returns the recorded result.

### Pidfds (Linux)

`pidfd` opens a pollable reference to the child, and `poll_exit(timeout)` waits on it. Spawned children get a pidfd automatically when the kernel supports it, and signals are then delivered through it, which rules out signalling a recycled pid.

## Controlling a terminal

### Scoped modes

```crystal
TTY.raw(STDIN) { STDIN.read_char }
TTY.cbreak(STDIN) { STDIN.read_char }
```

`TTY.with_terminal` combines a mode with individual switches and descriptor flags:

```crystal
TTY.with_terminal(STDIN, cbreak: true, signals: false, nonblocking: true) do
  # ...
end
```

Its options are `raw`, `cbreak`, `nonblocking`, `echo`, `canonical`, and `signals`, each `true` or `false`; `raw` and `cbreak` are mutually exclusive. All three helpers restore exactly what they changed, even when the block raises, and return the block's value.

### Termios values

`TTY::Termios` is a plain struct holding a terminal's attributes. Read it with `TTY.termios(fd)` and write it with `#set(fd)` or `PTY#termios=`.

```crystal
termios = TTY.termios(STDIN)
termios.echo?
termios.canonical = false
termios.set(STDIN)
```

`echo`, `canonical`, and `signals` are named switches for the most common local flags. `raw` and `cbreak` return modified copies; `make_raw` and `make_cbreak` change the value in place.

```crystal
original = pty.termios
pty.termios = original.raw
pty.termios = original
```

To read, change, and apply in one call, use `TTY.modify_termios` or `PTY#modify_termios`. The block receives the current attributes and returns the ones to apply:

```crystal
TTY.modify_termios(STDIN) do |termios|
  termios.echo = false
  termios
end

pty.modify_termios(&.raw)
```

Because termios is a value type, a block that only assigns would change a copy and do nothing; such a block is rejected at compile time.

Every flag is still available through `input`, `output`, `control`, and `local` (typed flag enums), control characters through `termios[TTY::ControlChar::Min]`, the line speed through `baud`, and VMIN/VTIME through `read_timeout`. `puts termios` prints an `stty`-style summary. On Linux, `TTY::Termios2` sets arbitrary baud rates.

### Declarative configuration

`TTY.configure` applies a list of changes on top of the current settings. Flag names are checked at compile time, and a typo fails the build with the list of valid names.

```crystal
TTY.configure(STDIN) do
  cbreak
  local -Echo, -IExten
  input +ICrNl
  cc min: 1, time: 0
  baud B9600
  action :drain
end
```

### Window size

```crystal
TTY.winsize(STDIN).cols
TTY::Winsize.current(STDIN)
pty.winsize = TTY::Winsize.new(24_u16, 80_u16)
```

`Winsize.current` returns `nil` when the descriptor is not a terminal. `TTY.on_resize(fd) { |size| ... }` runs a block on every resize, and `Winsize.propagate(from, to)` keeps one terminal the same size as another, immediately and on every resize.

## Working with a PTY directly

`TTY::PTY.open` allocates a master/slave pair without starting a program.

```crystal
pty = TTY::PTY.open
pty.slave_name
pty.write_master("input for the slave side\n")
pty.read_slave(Bytes.new(64))
pty.close
```

- `master_fd`, `slave_fd`: the raw descriptors; `master_io` and `slave_io` wrap them as `IO::FileDescriptor`.
- `read_master`, `write_master`, `read_slave`, `write_slave`, and vectored `read_master_v`/`write_master_v` are direct blocking I/O.
- `io` returns the fiber-aware `PTY::IO` over the master, the same object a `PTY::Process` reads through. It is created on first use, switches the master to nonblocking mode, and is reused afterwards. Do not mix it with the direct master calls.
- After the slave side is gone, master reads report end of stream instead of raising `EIO`; set `eof_on_error = false` to get the error.
- `close` is idempotent and closes every wrapper that was handed out.

### Packet mode

In packet mode each master read returns either data or a control packet describing flushes and flow-control changes.

```crystal
pty.packet_mode = true
buffer = Bytes.new(128)
packet = pty.read_packet(buffer)
packet.data? ? String.new(buffer[0, packet.size]) : packet.events
```

`wait_priority(timeout)` waits for a control packet.

## Descriptors and readiness

### Waiting on descriptors

```crystal
TTY.wait_readable(STDIN, 500.milliseconds)
TTY.wait_writable(fd, 0)

watches = [
  TTY::PollFd.watch(first, TTY::IOEvent::Readable),
  TTY::PollFd.watch(second, TTY::IOEvent::Readable),
]
TTY.poll(watches, 1.second)
watches.select(&.readable?)
```

The single-descriptor waits also return `true` on hang-up or error, so a closed peer never blocks forever.

### Poller

`TTY::Poller` keeps a watch set between waits. It uses `epoll` on Linux and `kqueue` on macOS; `TTY::Poller.poll` selects plain `poll` explicitly.

```crystal
poller = TTY::Poller.new
poller.watch(STDIN, TTY::IOEvent::Readable)
poller.wait(1.second).each { |event| event.fd if event.readable? }
poller.close
```

### Descriptor utilities

`TTY::FD` covers status and descriptor flags (`nonblocking?`, `set_nonblocking`, `cloexec?`, `set_cloexec`), `pipe`, `dup3`, `duplicate_cloexec`, `readv`/`writev`, `stat`, and on Linux `close_range` plus the zero-copy `splice`, `tee`, and `copy_file_range`.

## Sessions and serial lines

`TTY::Session` manages sessions and job control: `start` (`setsid`), `make_controlling`, `detach`, `id`, `foreground_pgrp`, `set_foreground_pgrp`, `process_group`, `set_process_group`, `signal_process_group`, line disciplines, and exclusive mode.

For serial devices, the top-level `TTY` module provides queue inspection (`pending_input`, `pending_output`), `flush`, `drain`, break control, software flow control, modem lines (`modem_status`, `set_modem_lines`, `clear_modem_lines`, `wait_modem`), interrupt counters (`serial_icount`), and byte injection (`inject`).

## Conventions

The public API accepts the same three kinds of arguments everywhere:

| Alias | Accepts | Meaning |
| --- | --- | --- |
| `TTY::Descriptor` | `Int32`, `IO::FileDescriptor` | Any descriptor, for example `STDIN` or a raw fd |
| `TTY::Timeout` | `nil`, `Int32`, `Time::Span` | `nil` waits forever, `0` checks once, an `Int32` counts milliseconds (`-1` also means forever), a span is rounded up to milliseconds |
| `TTY::SignalValue` | `Int32`, `Signal` | A signal |

`wait(timeout)` and `wait_event(timeout)` on a process require a non-negative timeout. The conversions are public as `TTY.fd_of`, `TTY.timeout_ms`, and `TTY.signal_number`.

Errors:

- `TTY::Syscall::Error` for failed system calls, with `errno`, `errno_name`, `operation`, and, where they apply, `fd`, `path`, and `request`
- `TTY::PTY::ExecError` when a program cannot be started
- `TTY::PTY::Error` for misuse of a PTY, such as I/O after `close`
- The standard `IO::TimeoutError`, `IO::EOFError`, and `IO::Error` from the IO layer
- `TTY::Error`, the base class of the shard's own errors

## Concurrency

- **Event loop.** `PTY::IO` and the `PTY::Process` IO methods, including `expect` and `send_line`, go through the Crystal event loop and suspend only the calling fiber. The direct calls (`TTY::Syscall`, `PTY#read_master`, blocking `wait`) block the whole thread in the default single-threaded runtime.
- **Bounded waits.** Timed waits (`wait(timeout)`, `wait_event(timeout)`, `wait_readable`) are safe to use from fibers. `PTY.run`, the block form of `PTY.spawn`, and `interact` end with a blocking `wait` after the program's output has ended or its terminal has been hung up.
- **Ownership.** A `PTY`, `PTY::Process`, or `Poller` is not internally synchronized; let one fiber own it at a time.
- **Closing descriptors.** Close the `IO`, not the raw fd. Closing a descriptor the event loop knows about with `Syscall.close` leaves a stale registration that affects the next descriptor reusing that number. Closing a `PTY` or its IO wakes any fiber blocked on it with `IO::Error`.
- **Child reaping.** Crystal's runtime reaps children on `SIGCHLD`. `wait` and `wait_event` recover the status the runtime recorded, so the exact exit status is never lost unless the child is reaped outside both this shard and the runtime.
- **Resize handlers.** `on_resize` and `Winsize.propagate` install a process-wide `SIGWINCH` handler that replaces any previous one, and the descriptor they watch must stay open.
- **Between fork and exec.** The spawn path performs no allocation and no stdlib calls in the child. Keep it that way if you change it.

## Platform support

Everything works on Linux. On macOS the portable core works: spawning, IO, expect, interact, termios, window size, sessions, readiness, and the `kqueue` poller.

Linux-only APIs are compile-time errors on macOS: a call to one fails the build with a message such as `TTY.flow_control is Linux-only`, and code that never calls them compiles normally. This covers `termios2` custom baud rates, `close_range`, `splice`/`tee`/`copy_file_range`, `fstat`, `wait_event`, pidfds, `epoll`, packet-mode and lock queries, flow control, modem-line set/clear/wait, and serial counters. `TTY::EpollPoller` exists only on Linux and `TTY::KqueuePoller` only on macOS; asking `Poller.new` for the other platform's backend raises `TTY::Error`.

## API reference

Every `fd` parameter is a `TTY::Descriptor`, every `timeout` a `TTY::Timeout`, and every `signal` a `TTY::SignalValue` unless stated otherwise.

### `TTY::PTY` (class methods)

`open`  
Allocate a master/slave pair; returns `PTY`  

`spawn(command, args = [] of String, **options)`  
Start a program on a new PTY; returns `PTY::Process`  

`spawn(command, args, options : SpawnOptions)`  
Same, with an options value; returns `PTY::Process`  

`spawn(command, args = [] of String, **options) { |process| }`  
Start, yield, then hang up, reap, and close; returns the block's value  

`spawn(command, args, options : SpawnOptions) { |process| }`  
Same, with an options value; returns the block's value  

`run(command, args = [] of String, **options)`  
Capture all output and the exit status; returns `{String, ChildStatus}`  

`run(command, args, options : SpawnOptions)`  
Same, with an options value; returns `{String, ChildStatus}`  

`wait(pid : Int32)`  
Blocking wait for any pid; returns `ChildStatus`  

### `TTY::PTY` (instance)

`master_fd`, `slave_fd`, `slave_name`  
Raw descriptors and slave device path  

`io`  
Fiber-aware `PTY::IO` over the master, created once  

`master_io`, `slave_io`  
`IO::FileDescriptor` wrappers, closed with the PTY  

`read_master(buffer)`, `write_master(data)`  
Blocking master I/O  

`read_master_v(buffers)`, `write_master_v(buffers)`  
Vectored master I/O  

`read_slave(buffer)`, `write_slave(data)`  
Blocking slave I/O  

`wait_readable(timeout = nil)`, `wait_writable(timeout = nil)`, `wait_priority(timeout = nil)`  
Master readiness  

`termios`, `termios=`, `modify_termios { }`  
Terminal attributes  

`winsize`, `winsize=`  
Window size  

`packet_mode=`, `packet_mode?`, `read_packet(buffer)`  
Packet mode (`packet_mode?` is Linux-only)  

`locked?`  
Slave lock state (Linux-only)  

`eof_on_error`, `eof_on_error=`  
End of stream instead of `EIO` after hang-up; default `true`  

`close_slave`, `close`, `closed?`  
Release descriptors  

### `TTY::PTY::Process < IO`

`pid`, `pty`, `io`  
Child pid, owned PTY, and its evented IO  

`read`, `write`, `flush`, `closed?` and all `IO` methods  
I/O with the child  

`expect(pattern, timeout = nil)`  
Read until a `Regex` or `String` matches; returns `Regex::MatchData`  

`send_line(line = "")`  
Write the line and `\r`  

`interact(input = STDIN, output = STDOUT)`  
Relay both ways until output ends; returns `ChildStatus`  

`wait`  
Block until exit; returns `ChildStatus`  

`wait(timeout)`  
`ChildStatus?`; `nil` on timeout  

`wait_event`, `wait_event(timeout)`  
Next `ChildEvent` from `waitid` (Linux-only)  

`status`, `last_event`, `exited?`  
Cached results  

`signal(signal)`, `terminate`, `kill`  
Send signals  

`pidfd`, `pidfd?`, `poll_exit(timeout = nil)`  
Pidfd access and exit polling (`pidfd` and `poll_exit` are Linux-only)  

`close`  
Close the pidfd and the PTY  

### `TTY::PTY::IO < IO`

`new(pty, eof_on_error = nil)`  
Wrap a PTY's master; raises `PTY::Error` if one already exists  

`expect(pattern, timeout = nil)`, `send_line(line = "")`  
Scripting helpers  

`sync?`, `sync=`  
Unbuffered writes; default `true`  

`read_timeout`, `read_timeout=`, `write_timeout`, `write_timeout=`  
Event-loop timeouts  

`eof_on_error`, `eof_on_error=`  
End of stream instead of `EIO`  

`pty`, `fd`, `io`  
Owning PTY, master fd, underlying `IO::FileDescriptor`  

### `TTY::SpawnOptions`

`new(env = nil, clear_env = false, shell = false, winsize = nil, working_dir = nil, close_fds = true)`  
Build options; `env` accepts any `Process::Env`  

`env`, `env=`  
Entries applied to the environment, `Hash(String, String?)`  

`clear_env`, `shell`, `winsize`, `working_dir`, `close_fds`  
Properties matching the options table  

`environment`  
Resolved child environment  

`argv(command, args)`  
Resolved argument vector  

### Statuses and events

`exit_code`, `normal_exit?`, `signal_exit?`, `exit_signal`  
`Process::Status` names; on `ChildStatus` and `ChildEvent`  

`exited?`, `exit_status`, `signaled?`, `term_signal`, `stopped?`, `core_dumped?`, `success?`  
Traditional status checks; on `ChildStatus` and `ChildEvent`  

`kind`, `pid`, `uid`, `status`  
Event fields; on `ChildEvent`  

`stop_signal`, `continued?`, `trapped?`, `terminal?`, `wait_status`  
Event checks and the traditional wait status word; on `ChildEvent`  

`ChildEvent.from_wait_status(pid, status)`  
Build an event from a traditional wait status word  

`TTY::ChildEventKind` is `None`, `Exited`, `Killed`, `Dumped`, `Trapped`, `Stopped`, or `Continued`.

### Terminal modes

`TTY.termios(fd)`, `TTY.winsize(fd)`  
Read attributes or size  

`TTY.raw(fd, action = SetAction::Now) { }`, `TTY.cbreak(fd, action = SetAction::Now) { }`  
Scoped modes  

`TTY.modify_termios(fd, action = SetAction::Now) { |termios| }`  
Apply the termios the block returns  

`TTY.with_terminal(fd, **options) { }`  
Macro: scoped mode, switches, and nonblocking flag  

`TTY.configure(fd) { }`  
Macro: declarative termios changes  

`TTY.flush(fd, queue = FlushQueue::Both)`  
Discard queued input and/or output  

`TTY.on_resize(fd) { |winsize| }`  
Run a block on `SIGWINCH`  

### `TTY::Termios`

`Termios.get(fd)`, `#set(fd, action = SetAction::Now)`  
Read and write  

`echo?`, `echo=`, `canonical?`, `canonical=`, `signals?`, `signals=`  
Named switches, listed in `Termios::SWITCHES`  

`raw`, `cbreak`  
Modified copies  

`make_raw`, `make_cbreak`  
Modify in place  

`input`, `output`, `control`, `local` and their setters  
`InputFlag`, `OutputFlag`, `ControlFlag`, `LocalFlag`  

`[](cc)`, `[]=(cc, value)`  
Control characters by `ControlChar`  

`baud`, `baud=`, `custom_baud?`  
Line speed by `Baud`  

`read_timeout`, `read_timeout=`  
VMIN/VTIME as a `Time::Span?`  

`line`, `line=`  
Line discipline (always `0` on macOS)  

`to_s(io)`  
`stty`-style summary  

`TTY::Termios2` (Linux-only) mirrors `get`, `set`, the flag accessors, `line`, and control characters, and adds `from(termios)`, `custom_baud=`, `custom_baud?`, `input_speed`, and `output_speed`.

`TTY::SetAction` is `Now`, `Drain`, or `Flush`; `TTY::FlushQueue` is `Input`, `Output`, or `Both`.

### `TTY::Winsize`

`new(rows = 0, cols = 0, xpixel = 0, ypixel = 0)`  
`UInt16` fields, all mutable  

`Winsize.get(fd)`, `#set(fd)`  
Read and write  

`Winsize.current(fd = 0)`  
Size, or `nil` for a non-terminal  

`Winsize.propagate(from_fd, to_fd)`  
Copy now and on every resize  

### Readiness and polling

`TTY.wait_readable(fd, timeout = nil)`, `wait_writable`, `wait_priority`  
Single-descriptor waits  

`TTY.wait_io(fd, events, timeout = nil)`  
Wait for an explicit `IOEvent` mask  

`TTY.poll(fds, timeout = nil)`  
Poll an `Array` or `Slice` of `PollFd`  

`PollFd.watch(fd, events)`  
Build a watch; inspect it with `readable?`, `priority?`, `writable?`, `error?`, `hangup?`, `invalid?`  

`Poller.new(backend = PollerBackendKind::Auto)`, `Poller.poll`  
Create a poller  

`Poller#watch(fd, events)`, `#unwatch(fd)`  
Manage the watch set  

`Poller#wait(timeout = nil)`  
`Array(PollerEvent)`, each with `fd`, `events`, and the same predicates as `PollFd`  

`Poller#backend`, `#close`, `#closed?`  
Introspection and teardown  

`TTY::IOEvent` flags are `Readable`, `Priority`, `Writable`, `Error`, `HangUp`, and `Invalid`; `TTY::PollerBackendKind` is `Auto`, `Poll`, `Epoll`, or `Kqueue`.

### `TTY::FD`

`status_flags(fd)`, `descriptor_flags(fd)`  
Raw `F_GETFL` and `F_GETFD`  

`nonblocking?(fd)`, `set_nonblocking(fd, enabled = true)`  
`O_NONBLOCK`; also available as `TTY.nonblocking?` and `TTY.set_nonblocking`  

`cloexec?(fd)`, `set_cloexec(fd, enabled = true)`  
`FD_CLOEXEC`; also available as `TTY.cloexec?` and `TTY.set_cloexec`  

`pipe(cloexec = true)`  
`{read_fd, write_fd}`  

`duplicate_cloexec(fd, minimum_fd = 0)`  
Duplicate with close-on-exec  

`readv(fd, buffers)`, `writev(fd, buffers)`  
Vectored I/O  

`dup3(old_fd, new_fd, cloexec = true)`  
Duplicate onto a number (Linux-only)  

`close_range(first, last = Int32::MAX)`  
Close a range, with a `/proc/self/fd` fallback (Linux-only)  

`splice`, `tee`, `copy_file_range`  
Zero-copy transfers (Linux-only)  

`stat(fd)`, `mode(fd)`, `character_device?(fd)`  
File metadata (Linux-only)  

### Sessions and serial lines

`Session.start`  
`setsid`; returns the new session id  

`Session.make_controlling(fd)`, `Session.detach(fd)`  
Acquire or release the controlling terminal  

`Session.id(fd)`  
Session of a terminal  

`Session.foreground_pgrp(fd)`, `Session.set_foreground_pgrp(fd, pgrp)`  
Foreground process group  

`Session.process_group(pid = 0)`, `Session.set_process_group(pid, pgrp)`  
Process groups (Linux-only)  

`Session.signal_process_group(pgrp, signal)`  
Signal a process group  

`Session.line_discipline(fd)`, `Session.set_line_discipline(fd, discipline)`  
Line discipline  

`Session.exclusive(fd, enable = true)`, `Session.exclusive?(fd)`  
Exclusive mode (`exclusive?` is Linux-only)  

`TTY.pending_input(fd)`, `TTY.pending_output(fd)`  
Queued byte counts  

`TTY.drain(fd)`, `TTY.send_break(fd)`, `TTY.clear_break(fd)`  
Output drain and break control  

`TTY.inject(fd, byte)`  
Push a byte into the input queue  

`TTY.modem_status(fd)`, `TTY.set_modem_status(fd, lines)`  
Modem lines as `ModemLine` flags  

`TTY.set_modem_lines`, `TTY.clear_modem_lines`, `TTY.wait_modem`  
Modem line changes (Linux-only)  

`TTY.flow_control(fd, action)`  
Software flow control by `FlowAction` (Linux-only)  

`TTY.serial_icount(fd)`, `TTY.output_empty?(fd)`  
Serial counters and line status (Linux-only)  

### `TTY::Syscall`

The raw layer the rest of the shard is built on. It takes plain `Int32` descriptors, millisecond timeouts, and signal numbers, and raises `Syscall::Error` for negative returns.

Core  
`raw(nr, a1..a6)`, `check(ret, ...)`  

I/O  
`read`, `write`, `readv`, `writev`, `close`, `fcntl`, `ioctl`, `ioctl_result`, `openat`, `fstat`  

Descriptors  
`pipe2`, `dup2`, `dup3`, `close_range`, `close_fds_from`, `close_fds_via_procfs`, `socketpair`  

Zero-copy  
`splice`, `tee`, `copy_file_range`  

Processes  
`fork`, `execve`, `setsid`, `setpgid`, `getpgid`, `getpid`, `kill`, `killpg`, `wait4`, `waitid`, `exit_group`, `reset_child_signal_state`  

Pidfds  
`pidfd_open`, `pidfd_send_signal`  

Polling  
`poll`, `sleep_ms`, `epoll_create1`, `epoll_ctl`, `epoll_wait`, `kqueue`, `kevent`  

Constants such as `WNOHANG`, `WNOWAIT`, `EINTR`, `EIO`, `EAGAIN`, `SIGTERM`, and `O_CLOEXEC` use the host platform's values.

## Development

```sh
crystal spec
crystal run examples/pty_process.cr
crystal run --release bench/pty_throughput.cr
```

- `spec/` holds the test suite, which needs Crystal 1.19 or newer. The library itself supports 1.10.
- `examples/` holds one small runnable program per feature area.
- `bench/` holds benchmarks for raw syscalls, PTY throughput, poller latency, and the macro layer.

The exclusive-mode spec expects `EBUSY` when a second process opens a locked terminal. The kernel does not enforce exclusive mode for root, so that spec fails when the suite runs as root.

## License

MIT
