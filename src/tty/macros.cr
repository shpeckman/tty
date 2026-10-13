# src/tty/macros.cr
module TTY
  macro configure(fd, &block)
    %fd = TTY.fd_of({{fd}})
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

  macro with_terminal(fd, **options, &block)
    {% switches = TTY::Termios::SWITCHES %}
    {% valid = ["raw", "cbreak", "nonblocking"] + switches.keys.map(&.stringify) %}
    {% for key, value in options %}
      {% unless valid.includes?(key.stringify) %}
        {% raise "unknown with_terminal option #{key.id}; valid options: #{valid.join(", ").id}" %}
      {% end %}
      {% unless value.is_a?(BoolLiteral) %}
        {% raise "with_terminal :#{key.id} must be true or false" %}
      {% end %}
    {% end %}
    {% raw = options[:raw] %}
    {% cbreak = options[:cbreak] %}
    {% nonblocking = options[:nonblocking] %}
    {% if raw && cbreak %}
      {% raise "with_terminal accepts raw or cbreak, not both" %}
    {% end %}
    {% toggled = switches.keys.select { |name| !options[name].is_a?(NilLiteral) } %}
    {% configure_termios = raw || cbreak || !toggled.empty? %}
    %fd = TTY.fd_of({{fd}})
    {% if configure_termios %}
      %termios = TTY::Termios.get(%fd)
    {% end %}
    {% if nonblocking.is_a?(BoolLiteral) %}
      %status_flags = TTY::FD.status_flags(%fd)
    {% end %}
    begin
      {% if configure_termios %}
        %configured = %termios
        {% if raw %}
          %configured.make_raw
        {% elsif cbreak %}
          %configured.make_cbreak
        {% end %}
        {% for name in toggled %}
          %configured.{{name.id}} = {{options[name]}}
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
      {% if configure_termios %}
        %termios.set(%fd)
      {% end %}
    end
  end

  macro spawn(command, args = nil, &block)
    {% scalars = {"working_dir" => false, "close_fds" => true, "clear_env" => true, "shell" => true} %}
    {% statements = block.body.is_a?(Expressions) ? block.body.expressions : [block.body] %}
    {% env_pairs = [] of ASTNode %}
    {% winsize_statement = nil %}
    {% scalar_values = {} of StringLiteral => ASTNode %}
    {% for statement in statements %}
      {% unless statement.is_a?(Nop) %}
      {% unless statement.is_a?(Call) %}
        {% statement.raise "expected a spawn option statement (env, winsize, #{scalars.keys.join(", ").id})" %}
      {% end %}
      {% name = statement.name.stringify %}
      {% if name == "env" %}
        {% if statement.args.size == 1 && statement.args[0].is_a?(HashLiteral) %}
          {% for key, index in statement.args[0].keys %}
            {% unless key.is_a?(StringLiteral) %}
              {% key.raise "env hash keys must be strings" %}
            {% end %}
            {% env_pairs << {key, statement.args[0].values[index]} %}
          {% end %}
        {% elsif statement.args.empty? %}
          {% for entry in statement.named_args %}
            {% env_pairs << {entry.name.stringify.upcase, entry.value} %}
          {% end %}
        {% else %}
          {% statement.raise "env accepts named entries (keys are upcased), e.g. env path: \"/bin\", or a single hash literal for exact-case keys" %}
        {% end %}
      {% elsif name == "winsize" %}
        {% unless statement.args.empty? %}
          {% statement.raise "winsize accepts named entries only, e.g. winsize rows: 24, cols: 80" %}
        {% end %}
        {% for entry in statement.named_args %}
          {% unless ["rows", "cols", "xpixel", "ypixel"].includes?(entry.name.stringify) %}
            {% entry.raise "unknown winsize field #{entry.name.id}; valid fields: rows, cols, xpixel, ypixel" %}
          {% end %}
        {% end %}
        {% winsize_statement = statement %}
      {% elsif scalars.keys.includes?(name) %}
        {% if statement.args.size != 1 %}
          {% statement.raise "#{name.id} accepts a single value" %}
        {% end %}
        {% if scalars[name] && !statement.args[0].is_a?(BoolLiteral) %}
          {% statement.raise "#{name.id} accepts true or false" %}
        {% end %}
        {% scalar_values[name] = statement.args[0] %}
      {% else %}
        {% statement.raise "unknown spawn option #{name.id}; expected env, winsize, #{scalars.keys.join(", ").id}" %}
      {% end %}
      {% end %}
    {% end %}
    TTY::PTY.spawn(
      {{command}},
      {% if args %}{{args}}{% else %}[] of String{% end %},
      {% unless env_pairs.empty? %}
        env: {
          {% for pair in env_pairs %}
            ({{pair[0]}}) => ({{pair[1]}}),
          {% end %}
        } of String => String?,
      {% end %}
      {% if winsize_statement %}
        winsize: TTY::Winsize.new(
          {% for entry in winsize_statement.named_args %}
            {{entry.name.id}}: {{entry.value}},
          {% end %}
        ),
      {% end %}
      {% for name, value in scalar_values %}
        {{name.id}}: {{value}},
      {% end %}
    )
  end
end
