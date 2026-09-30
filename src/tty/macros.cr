# src/tty/macros.cr
module TTY
  macro configure(fd, &block)
    %fd = {{fd}}
    %termios = TTY::Termios.get(%fd)
    %action = TTY::SetAction::Now
    {% statements = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
    {% for statement in statements %}
      {% unless statement.is_a?(Nop) %}
      {% unless statement.is_a?(Call) %}
        {% statement.raise "expected a terminal configuration statement (raw, cbreak, input, output, control, local, cc, baud, action)" %}
      {% end %}
      {% if statement.name == :raw %}
        %termios.make_raw
      {% elsif statement.name == :cbreak %}
        %termios.make_cbreak
      {% elsif statement.name == :input || statement.name == :output || statement.name == :control || statement.name == :local %}
        {% scope = {"input" => TTY::InputFlag, "output" => TTY::OutputFlag, "control" => TTY::ControlFlag, "local" => TTY::LocalFlag}[statement.name.stringify] %}
        {% for flag in statement.args %}
          {% if flag.is_a?(Call) && (flag.name == "-" || flag.name == "+") && flag.receiver.is_a?(Path) %}
            {% flag_name = flag.receiver.names.last.stringify %}
          {% elsif flag.is_a?(Path) %}
            {% flag_name = flag.names.last.stringify %}
          {% else %}
            {% flag.raise "expected a flag such as +Echo or -ICanon" %}
          {% end %}
          {% unless scope.constants.map(&.stringify).includes?(flag_name) %}
            {% flag.raise "unknown #{scope} flag #{flag_name.id}; valid flags: #{scope.constants.join(", ").id}" %}
          {% end %}
          {% if flag.is_a?(Call) && flag.name == "-" %}
            %termios.{{statement.name.id}} = %termios.{{statement.name.id}} & ~{{scope}}::{{flag_name.id}}
          {% else %}
            %termios.{{statement.name.id}} = %termios.{{statement.name.id}} | {{scope}}::{{flag_name.id}}
          {% end %}
        {% end %}
      {% elsif statement.name == :cc %}
        {% unless statement.args.empty? %}
          {% statement.raise "cc accepts named entries only, e.g. cc min: 1, time: 0" %}
        {% end %}
        {% for entry in statement.named_args %}
          {% matches = TTY::ControlChar.constants.select { |constant| constant.stringify.downcase == entry.name.stringify } %}
          {% if matches.empty? %}
            {% entry.raise "unknown control character #{entry.name.id}; valid names: #{TTY::ControlChar.constants.join(", ").id}" %}
          {% end %}
          %termios[TTY::ControlChar::{{matches[0].id}}] = ({{entry.value}}).to_u8
        {% end %}
      {% elsif statement.name == :baud %}
        {% if statement.args.size != 1 || !statement.args[0].is_a?(Path) %}
          {% statement.raise "baud accepts a single TTY::Baud member, e.g. baud B9600" %}
        {% end %}
        {% baud_name = statement.args[0].names.last.stringify %}
        {% unless TTY::Baud.constants.map(&.stringify).includes?(baud_name) %}
          {% statement.raise "unknown baud rate #{baud_name.id}; valid rates: #{TTY::Baud.constants.join(", ").id}" %}
        {% end %}
        %termios.baud = TTY::Baud::{{baud_name.id}}
      {% elsif statement.name == :action %}
        {% if statement.args.size != 1 %}
          {% statement.raise "action accepts a single value: :now, :drain, :flush or a TTY::SetAction member" %}
        {% end %}
        {% value = statement.args[0] %}
        {% if value.is_a?(SymbolLiteral) %}
          {% mapped = {"now" => "Now", "drain" => "Drain", "flush" => "Flush"}[value.id.stringify] %}
          {% unless mapped %}
            {% value.raise "unknown action #{value.id}; expected :now, :drain or :flush" %}
          {% end %}
          %action = TTY::SetAction::{{mapped.id}}
        {% elsif value.is_a?(Path) %}
          %action = {{value}}
        {% else %}
          {% value.raise "unknown action #{value.id}; expected :now, :drain or :flush" %}
        {% end %}
      {% else %}
        {% statement.raise "unknown configure statement #{statement.name.id}; expected raw, cbreak, input, output, control, local, cc, baud or action" %}
      {% end %}
      {% end %}
    {% end %}
    %termios.set(%fd, %action)
  end

  macro with_terminal(fd, raw = false, cbreak = false, nonblocking = nil, &block)
    {% if raw && cbreak %}
      {% raise "with_terminal accepts raw or cbreak, not both" %}
    {% end %}
    {% unless nonblocking.is_a?(NilLiteral) || nonblocking.is_a?(BoolLiteral) %}
      {% raise "with_terminal :nonblocking must be true or false" %}
    {% end %}
    %fd = {{fd}}
    {% if raw || cbreak %}
      %termios = TTY::Termios.get(%fd)
    {% end %}
    {% if nonblocking.is_a?(BoolLiteral) %}
      %status_flags = TTY::FD.status_flags(%fd)
    {% end %}
    begin
      {% if raw || cbreak %}
        %configured = %termios
        {% if raw %}
          %configured.make_raw
        {% else %}
          %configured.make_cbreak
        {% end %}
        %configured.set(%fd)
      {% end %}
      {% if nonblocking.is_a?(BoolLiteral) %}
        TTY::FD.set_nonblocking(%fd, {{nonblocking}})
      {% end %}
      {{block.body}}
    ensure
      {% if nonblocking.is_a?(BoolLiteral) %}
        TTY::Syscall.fcntl(%fd, TTY::Syscall::F_SETFL, %status_flags.to_i64)
      {% end %}
      {% if raw || cbreak %}
        %termios.set(%fd)
      {% end %}
    end
  end

  macro spawn(command, args = nil, &block)
    {% statements = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
    {% env_count = 0 %}
    {% winsize_statement = nil %}
    {% working_dir_value = nil %}
    {% close_fds_value = nil %}
    {% for statement in statements %}
      {% unless statement.is_a?(Nop) %}
      {% unless statement.is_a?(Call) %}
        {% statement.raise "expected a spawn option statement (env, winsize, working_dir, close_fds)" %}
      {% end %}
      {% if statement.name == :env %}
        {% if statement.args.size == 1 && statement.args[0].is_a?(HashLiteral) %}
          {% for key in statement.args[0].keys %}
            {% unless key.is_a?(StringLiteral) %}
              {% key.raise "env hash keys must be strings" %}
            {% end %}
          {% end %}
          {% env_count += statement.args[0].keys.size %}
        {% elsif statement.args.empty? %}
          {% env_count += statement.named_args.size %}
        {% else %}
          {% statement.raise "env accepts named entries (keys are upcased), e.g. env path: \"/bin\", or a single hash literal for exact-case keys" %}
        {% end %}
      {% elsif statement.name == :winsize %}
        {% unless statement.args.empty? %}
          {% statement.raise "winsize accepts named entries only, e.g. winsize rows: 24, cols: 80" %}
        {% end %}
        {% for entry in statement.named_args %}
          {% unless ["rows", "cols", "xpixel", "ypixel"].includes?(entry.name.stringify) %}
            {% entry.raise "unknown winsize field #{entry.name.id}; valid fields: rows, cols, xpixel, ypixel" %}
          {% end %}
        {% end %}
        {% winsize_statement = statement %}
      {% elsif statement.name == :working_dir %}
        {% if statement.args.size != 1 %}
          {% statement.raise "working_dir accepts a single path, e.g. working_dir \"/tmp\"" %}
        {% end %}
        {% working_dir_value = statement.args[0] %}
      {% elsif statement.name == :close_fds %}
        {% if statement.args.size != 1 || !statement.args[0].is_a?(BoolLiteral) %}
          {% statement.raise "close_fds accepts true or false" %}
        {% end %}
        {% close_fds_value = statement.args[0] %}
      {% else %}
        {% statement.raise "unknown spawn option #{statement.name.id}; expected env, winsize, working_dir or close_fds" %}
      {% end %}
      {% end %}
    {% end %}
    TTY::PTY.spawn({{command}}{% if args %}, {{args}}{% end %}{% if env_count > 0 %},
      env: TTY::SpawnOptions.default_env.merge({
        {% for statement in statements %}
          {% if statement.is_a?(Call) && statement.name == :env %}
            {% if statement.args.size == 1 && statement.args[0].is_a?(HashLiteral) %}
              {% for key, index in statement.args[0].keys %}
                ({{key}}) => ({{statement.args[0].values[index]}}),
              {% end %}
            {% else %}
              {% for entry in statement.named_args %}
                {{entry.name.stringify.upcase}} => ({{entry.value}}),
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      }){% end %}{% if winsize_statement %},
      winsize: TTY::Winsize.new(
        {% for entry in winsize_statement.named_args %}
          {{entry.name.id}}: {{entry.value}},
        {% end %}
      ){% end %}{% if working_dir_value %},
      working_dir: {{working_dir_value}}{% end %}{% if close_fds_value %},
      close_fds: {{close_fds_value}}{% end %})
  end
end
