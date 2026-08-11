# src/mvu.cr
require "set"

module MVU
  module Msg
  end

  enum Render
    EveryMessage
    Coalesced
  end

  class PrefixedId
    getter tag   : Symbol
    getter inner : SubId

    def initialize(@tag : Symbol, @inner : SubId)
    end

    def_equals_and_hash @tag, @inner

    def to_s(io : IO) : Nil
      io << @tag << ':' << @inner
    end
  end

  alias SubId = Symbol | Int32 | Int64 | PrefixedId

  struct Sub
    NONE   = [] of Sub
    NO_IDS = [] of SubId

    getter id   : SubId
    getter task : Proc(Proc(Msg, Nil), Channel(Nil), Nil)

    def initialize(@id : SubId, &@task : Proc(Msg, Nil), Channel(Nil) ->)
    end

    def map(tag : Symbol, &mapper : Msg -> Msg) : Sub
      Sub.new(PrefixedId.new(tag, @id)) do |dispatch, cancel|
        mapped_dispatch = ->(msg : Msg) { dispatch.call(mapper.call(msg)) }
        @task.call(mapped_dispatch, cancel)
      end
    end

    class Handle
      getter cancel : Channel(Nil)

      property generation : UInt32

      def initialize(@cancel : Channel(Nil), @generation : UInt32)
      end
    end
  end

  struct Cmd
    enum Mode : UInt8
      Sync
      Async
    end

    struct Task
      getter mode : Mode
      getter run  : Proc(Msg?)

      def initialize(@mode : Mode, @run : Proc(Msg?))
      end

      def map(&mapper : Msg -> Msg) : Task
        inner = @run

        Task.new(@mode, -> : Msg? {
          msg = inner.call
          msg ? mapper.call(msg) : nil
        })
      end
    end

    EMPTY = [] of Task
    NONE  = Cmd.new(EMPTY)

    getter tasks : Array(Task)

    def initialize(@tasks : Array(Task) = EMPTY)
    end

    def self.none : Cmd
      NONE
    end

    def self.sync(&block : -> Msg?) : Cmd
      new(Array(Task).new(1) << Task.new(Mode::Sync, block))
    end

    def self.of(&block : -> Msg?) : Cmd
      new(Array(Task).new(1) << Task.new(Mode::Async, block))
    end

    def self.batch(cmds : Array(Cmd)) : Cmd
      total = 0
      cmds.each { |cmd| total &+= cmd.tasks.size }

      return NONE if total == 0

      tasks = Array(Task).new(total)
      cmds.each { |cmd| tasks.concat(cmd.tasks) }

      new(tasks)
    end

    def empty? : Bool
      @tasks.empty?
    end

    def map(&mapper : Msg -> Msg) : Cmd
      return NONE if @tasks.empty?

      Cmd.new(@tasks.map { |task| task.map(&mapper) })
    end
  end

  module Model
    macro included
      macro finished
        \{% names = @type.methods.map(&.name.stringify) %}
        \{% if names.includes?("subscription_ids") && !names.includes?("subscription") %}
          \{% raise "#{@type} defines `subscription_ids` but not `subscription(id)`. Provide `def subscription(id : MVU::SubId) : MVU::Sub` returning the sub for each id." %}
        \{% end %}
        \{% if names.includes?("subscription") && !names.includes?("subscription_ids") %}
          \{% raise "#{@type} defines `subscription(id)` but not `subscription_ids`. Provide `def subscription_ids : Array(MVU::SubId)` listing the active ids." %}
        \{% end %}
      end
    end

    abstract def update(msg : Msg) : {self, Cmd}
    abstract def view : String

    def subscription_ids : Array(SubId)
      Sub::NO_IDS
    end

    def subscription(id : SubId) : Sub
      raise "#{self.class} has no subscription for #{id.inspect}"
    end
  end

  abstract class Middleware(M)
    abstract def call(model : M, msg : Msg, next_fn : Proc(M, Msg, {M, Cmd})) : {M, Cmd}
  end

  class Program(M)
    CAPACITY = 1024

    @queue         : Channel(Msg)
    @inbox         : Deque(Msg)
    @active_subs   : Hash(SubId, Sub::Handle)
    @generation    : UInt32
    @dispatch_proc : Proc(Msg, Nil)
    @update_fn     : Proc(M, Msg, {M, Cmd})
    @render        : Render
    getter model   : M

    def initialize(
      initial_model : M,
      initial_cmd : Cmd = Cmd.none,
      middlewares : Array(Middleware(M)) = [] of Middleware(M),
      render : Render = Render::EveryMessage,
    )
      @queue         = Channel(Msg).new(CAPACITY)
      @inbox         = Deque(Msg).new
      @active_subs   = Hash(SubId, Sub::Handle).new
      @generation    = 0_u32
      @model         = initial_model
      @render        = render
      @dispatch_proc = ->(msg : Msg) { dispatch(msg) }

      chain = ->(m : M, msg : Msg) { m.update(msg) }

      middlewares.reverse_each do |mw|
        next_fn    = chain
        current_mw = mw
        chain      = ->(m : M, msg : Msg) { current_mw.call(m, msg, next_fn) }
      end

      @update_fn = chain

      run_cmd(initial_cmd)
      reconcile
    end

    def dispatch(msg : Msg) : Nil
      @queue.send(msg)
    rescue Channel::ClosedError
    end

    def dispatch?(msg : Msg) : Bool
      select
      when @queue.send(msg)
        true
      else
        false
      end
    rescue Channel::ClosedError
      false
    end

    def stop : Nil
      @queue.close
    end

    def stopped? : Bool
      @queue.closed?
    end

    def run(&block : M ->) : Nil
      block.call(@model)

      unless @inbox.empty?
        pump(block)
        reconcile
        block.call(@model) if @render.coalesced?
      end

      while msg = @queue.receive?
        process(msg, block)
        drain(block)
        reconcile
        block.call(@model) if @render.coalesced?
      end

      shutdown
    end

    private def drain(render : Proc(M, Nil)) : Nil
      loop do
        select
        when queued = @queue.receive?
          break unless queued

          process(queued, render)
        else
          break
        end
      end
    end

    private def process(msg : Msg, render : Proc(M, Nil)) : Nil
      deliver(msg, render)
      pump(render)
    end

    private def pump(render : Proc(M, Nil)) : Nil
      while msg = @inbox.shift?
        deliver(msg, render)
      end
    end

    private def deliver(msg : Msg, render : Proc(M, Nil)) : Nil
      @model, cmd = @update_fn.call(@model, msg)

      run_cmd(cmd)
      render.call(@model) if @render.every_message?
    end

    private def shutdown : Nil
      @active_subs.each_value { |handle| handle.cancel.close }
      @active_subs.clear
      @inbox.clear
    end

    private def run_cmd(cmd : Cmd) : Nil
      tasks = cmd.tasks

      return if tasks.empty?

      tasks.each do |task|
        run = task.run

        case task.mode
        in .sync?
          msg = run.call
          @inbox << msg if msg
        in .async?
          spawn do
            produced = run.call
            dispatch(produced) if produced
          end
        end
      end
    end

    private def reconcile : Nil
      ids = @model.subscription_ids

      return if ids.empty? && @active_subs.empty?

      generation  = @generation &+ 1
      @generation = generation
      active      = @active_subs.size
      matched     = 0

      ids.each do |id|
        if handle = @active_subs[id]?
          matched &+= 1 unless handle.generation == generation
          handle.generation = generation
          next
        end

        sub    = @model.subscription(id)
        cancel = Channel(Nil).new
        task   = sub.task

        @active_subs[id] = Sub::Handle.new(cancel, generation)

        spawn do
          task.call(@dispatch_proc, cancel)
        end
      end

      return if matched == active

      @active_subs.reject! do |_, handle|
        next false if handle.generation == generation

        handle.cancel.close
        true
      end
    end
  end
end
