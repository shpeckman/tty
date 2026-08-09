# src/tty/mux.cr

require "wait_group"
require "./pty"

# Owns many `Pty` sessions and shuttles bytes between each master fd and a
# single tagged output stream, without interpreting the data. One owner fiber
# is the sole mutator of the session map: callers send `Command`s and pumps
# report exits, both serialised through a `select`, so `@sessions` needs no
# lock. Output frames bypass the owner and go straight to the public channel,
# so a slow consumer can't wedge command handling. Sessions are added
# dynamically; ids are minted by the owner and returned on spawn.
class TTY::Mux
  READ_BUFFER_SIZE = 4096
  OUTPUT_CAPACITY  =  256

  enum Kind
    Output
    Exited
  end

  # A tagged frame on the public output stream. `Output` carries a freshly
  # copied slice; `Exited` carries the reaped code (`nil` if signalled).
  record Frame,
    id        : UInt64,
    kind      : Kind,
    data      : Bytes  = Bytes.empty,
    exit_code : Int32? = nil

  # The outcome of a spawn request. `id` is set on success; `error` holds the
  # raised message on failure, so a bad spawn never unwinds the owner fiber.
  record SpawnResult,
    id    : UInt64?,
    error : String? = nil

  private enum Op
    Spawn
    Write
    Resize
    Kill
    Shutdown
  end

  private record Command,
    op      : Op,
    id      : UInt64                = 0_u64,
    command : String                = "",
    args    : Array(String)         = [] of String,
    cols    : Int32                 = 80,
    rows    : Int32                 = 24,
    env     : Process::Env          = nil,
    chdir   : String?               = nil,
    payload : Bytes | String        = "",
    reply   : Channel(SpawnResult)? = nil

  # The public output stream. Drain it with `mux.output.receive`. Pumps write
  # `Output` frames here directly, so a slow consumer applies backpressure to
  # the offending session's pump alone and never to the owner fiber — commands
  # (including `close`) always stay serviceable. `Exited` frames still route
  # through the owner so the map delete and the frame stay ordered.
  getter output : Channel(Frame)

  getter? closed = false
  @shutting_down = false

  def initialize
    @sessions = {} of UInt64 => Pty
    @commands = Channel(Command).new
    @exits    = Channel(Frame).new(OUTPUT_CAPACITY)
    @output   = Channel(Frame).new(OUTPUT_CAPACITY)
    @next_id  = 0_u64
    @deferred = WaitGroup.new
    spawn { run }
  end

  # Spawns a session and returns its result. On success `SpawnResult#id` is the
  # new session id; on failure `#error` explains why and `#id` is `nil`.
  # Blocks until the owner has processed the request.
  def spawn_session(command : String, args : Array(String) = [] of String,
                    cols : Int32 = 80, rows : Int32 = 24,
                    env : Process::Env = nil, chdir : String? = nil) : SpawnResult
    return SpawnResult.new(nil, "mux closed") if @closed
    reply = Channel(SpawnResult).new
    @commands.send Command.new(Op::Spawn, command: command, args: args,
      cols: cols, rows: rows, env: env, chdir: chdir, reply: reply)
    reply.receive
  end

  # Forwards input to a session. Dropped silently if the id is unknown or
  # already exited; the caller learns of the exit via an `Exited` frame.
  def write(id : UInt64, data : Bytes | String) : Nil
    return if @closed
    @commands.send Command.new(Op::Write, id: id, payload: data)
  end

  # Resizes a session's terminal. Dropped silently on an unknown id.
  def resize(id : UInt64, cols : Int32, rows : Int32) : Nil
    return if @closed
    @commands.send Command.new(Op::Resize, id: id, cols: cols, rows: rows)
  end

  # Hangs up a single session. Dropped silently on an unknown id; the pump's
  # EOF path emits the `Exited` frame and removes the entry.
  def kill(id : UInt64) : Nil
    return if @closed
    @commands.send Command.new(Op::Kill, id: id)
  end

  # Kills every session and stops the owner fiber. Idempotent. The public
  # `output` channel is closed once every pump has drained, so a consumer loop
  # of `while frame = output.receive?` terminates cleanly.
  def close : Nil
    return if @closed
    @closed = true
    @commands.send Command.new(Op::Shutdown)
  end

  private def run
    until @shutting_down && @sessions.empty?
      select
      when command = @commands.receive
        handle_command command
      when frame = @exits.receive
        handle_exit frame
      end
    end
    @deferred.wait
    @output.close
  end

  private def handle_command(command : Command)
    case command.op
    in Op::Spawn    then do_spawn command
    in Op::Write    then @sessions[command.id]?.try &.write(command.payload)
    in Op::Resize   then @sessions[command.id]?.try &.resize(command.cols, command.rows)
    in Op::Kill     then @sessions[command.id]?.try &.kill
    in Op::Shutdown then @shutting_down = true; do_shutdown
    end
  end

  private def do_spawn(command : Command)
    reply = command.reply.not_nil!
    begin
      pty = Pty.new(command.command, command.args, command.cols, command.rows,
        command.env, command.chdir)
      id = (@next_id += 1)
      @sessions[id] = pty
      spawn { pump id, pty }
      reply.send SpawnResult.new(id)
    rescue ex
      reply.send SpawnResult.new(nil, ex.message || ex.class.name)
    end
  end

  private def do_shutdown
    @sessions.each_value &.kill
  end

  private def handle_exit(frame : Frame)
    @sessions.delete frame.id
    select
    when @output.send frame
    else
      @deferred.spawn { @output.send frame }
    end
  end

  private def pump(id : UInt64, pty : Pty)
    buffer = Bytes.new(READ_BUFFER_SIZE)
    loop do
      bytes_read = pty.master.read(buffer)
      break if bytes_read.zero?
      @output.send Frame.new(id, Kind::Output, data: buffer[0, bytes_read].dup)
    end
  rescue IO::Error
  ensure
    code = pty.reap
    @exits.send Frame.new(id, Kind::Exited, exit_code: code)
  end
end
