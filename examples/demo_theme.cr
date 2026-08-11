# examples/demo_theme.cr
require "../src/tty"

LIGHT = "\e]21;0=#5c5f77;1=#d20f39;2=#40a02b;3=#df8e1d;4=#1e66f5;5=#ea76cb;6=#179299;7=#acb0be;8=#6c6f85;9=#d20f39;10=#40a02b;11=#df8e1d;12=#1e66f5;13=#ea76cb;14=#179299;15=#bcc0cc;16=#4c4f69;17=#4e5384;18=#4c589f;19=#465cbb;20=#3a61d8;21=#1e66f5;22=#505f60;23=#516279;24=#506592;25=#4c69ad;26=#416cc7;27=#2c70e2;28=#516f56;29=#52716e;30=#517386;31=#4d759e;32=#4477b7;33=#3179d0;34=#4f7f4a;35=#508062;36=#4f8079;37=#4b808f;38=#4281a6;39=#3082be;40=#4a903d;41=#4b8e55;42=#4a8d6b;43=#458c80;44=#3c8b96;45=#298aab;46=#40a02b;47=#419d46;48=#409a5c;49=#3b9771;50=#309585;51=#179299;52=#6e4b5f;53=#72517a;54=#745696;55=#745cb2;56=#7263cf;57=#6b69ed;58=#715c58;59=#746172;60=#76668c;61=#766ba7;62=#7271c3;63=#6b76e0;64=#726d4f;65=#757169;66=#767582;67=#75799d;68=#717eb7;69=#6982d3;70=#727e45;71=#74815f;72=#758478;73=#738792;74=#6e8bab;75=#658ec5;76=#708e39;77=#729054;78=#71926d;79=#6f9586;80=#69979f;81=#5f9ab8;82=#6c9f28;83=#6da047;84=#6ca161;85=#68a27a;86=#61a392;87=#56a5ab;88=#894656;89=#8f4d71;90=#94548d;91=#965ca9;92=#9664c6;93=#946ce4;94=#8c584f;95=#925f6a;96=#956686;97=#976da2;98=#9675bf;99=#927ddd;100=#8e6a48;101=#937063;102=#96777f;103=#967e9b;104=#9585b8;105=#908cd5;106=#8f7b3f;107=#93815c;108=#958778;109=#958e94;110=#9294b0;111=#8c9bcd;112=#8f8c34;113=#929153;114=#939770;115=#929d8c;116=#8ea3a8;117=#87aac5;118=#8d9c25;119=#8fa149;120=#8fa767;121=#8dac84;122=#88b2a0;123=#7fb8bd;124=#a33d4c;125=#aa4667;126=#af5083;127=#b35aa0;128=#b465be;129=#b46fdc;130=#a65247;131=#ac5b63;132=#b16580;133=#b46f9d;134=#b579bb;135=#b383da;136=#a86541;137=#ae6e5e;138=#b2787c;139=#b4819a;140=#b48cb8;141=#b296d7;142=#aa7739;143=#af8059;144=#b28a77;145=#b49396;146=#b39eb5;147=#afa8d5;148=#aa8830;149=#af9152;150=#b29b72;151=#b2a592;152=#b0afb2;153=#abb9d2;154=#aa9922;155=#aea24b;156=#b0ac6d;157=#b0b68d;158=#acc0ae;159=#a5cbcf;160=#bb2e43;161=#c23d5e;162=#c84b7a;163=#cd5897;164=#cf65b5;165=#d073d4;166=#be483f;167=#c5555c;168=#cb6279;169=#cf6f98;170=#d17db7;171=#d18ad7;172=#c15e3a;173=#c86a59;174=#cd7778;175=#d18598;176=#d292b8;177=#d1a0da;178=#c37133;179=#ca7e56;180=#cf8b77;181=#d29998;182=#d2a7ba;183=#d0b5dd;184=#c4832b;185=#cb9052;186=#cf9e75;187=#d2ac98;188=#d1bbbb;189=#cec9df;190=#c59420;191=#cba24d;192=#cfb173;193=#d1bf97;194=#cfcebc;195=#cadee2;196=#d20f39;197=#da2e55;198=#e04371;199=#e5558e;200=#e966ac;201=#ea76cb;202=#d63a36;203=#de4d54;204=#e45f73;205=#e97092;206=#ec80b2;207=#ed91d3;208=#d95432;209=#e16554;210=#e87675;211=#ec8796;212=#ef98b9;213=#efaadc;214=#db692d;215=#e47a53;216=#ea8c76;217=#ef9e9a;218=#f1b0bf;219=#f0c2e4;220=#dd7c27;221=#e68e51;222=#eda177;223=#f1b39e;224=#f2c6c5;225=#f0daed;226=#df8e1d;227=#e8a14f;228=#eeb578;229=#f2c8a1;230=#f2ddcb;231=#eff1f5;232=#52556e;233=#585b73;234=#5e6179;235=#64677e;236=#6a6d83;237=#717389;238=#77798e;239=#7d7f94;240=#848699;241=#8a8c9f;242=#9092a4;243=#9799aa;244=#9d9faf;245=#a4a6b5;246=#abacbb;247=#b1b3c0;248=#b8bac6;249=#bfc1cc;250=#c6c7d2;251=#ccced7;252=#d3d5dd;253=#dadce3;254=#e1e3e9;255=#e8eaef;foreground=#4c4f69;background=#eff1f5;selection_foreground=#eff1f5;selection_background=#dc8a78;cursor=#dc8a78;cursor_text=#eff1f5\e\\"

DARK = "\e]21;0=#45475a;1=#f38ba8;2=#a6e3a1;3=#f9e2af;4=#89b4fa;5=#f5c2e7;6=#94e2d5;7=#bac2de;8=#585b70;9=#f38ba8;10=#a6e3a1;11=#f9e2af;12=#89b4fa;13=#f5c2e7;14=#94e2d5;15=#a6adc8;16=#1e1e2e;17=#323852;18=#465579;19=#5c73a2;20=#7293cd;21=#89b4fa;22=#384044;23=#485763;24=#596f85;25=#6a88a8;26=#7ba2cd;27=#8dbdf3;28=#52655a;29=#5f7875;30=#6b8b91;31=#789eaf;32=#84b2cd;33=#90c6ec;34=#6d8d71;35=#759a87;36=#7da79e;37=#85b4b5;38=#8bc2cc;39=#92d0e4;40=#89b789;41=#8cbe99;42=#8fc4aa;43=#91cbbb;44=#92d2cc;45=#93d9dd;46=#a6e3a1;47=#a3e3ac;48=#a0e3b6;49=#9de2c0;50=#99e2cb;51=#94e2d5;52=#453244;53=#584a64;54=#6b6487;55=#7d7faa;56=#909ad0;57=#a3b7f6;58=#5c5257;59=#6b6773;60=#797c91;61=#8892b0;62=#96a8d0;63=#a3bff1;64=#727469;65=#7d8482;66=#88949b;67=#91a5b6;68=#9bb6d0;69=#a3c7ec;70=#89987d;71=#90a391;72=#95aea6;73=#9bb9bb;74=#9fc4d0;75=#a3d0e6;76=#a1bd90;77=#a2c2a0;78=#a3c7b0;79=#a3cdc0;80=#a3d2d0;81=#a2d8e1;82=#b8e3a4;83=#b5e2af;84=#b0e2ba;85=#ace1c5;86=#a7e0d0;87=#a1e0db;88=#6d475c;89=#7d5d78;90=#8d7395;91=#9c8ab3;92=#aba2d2;93=#babaf3;94=#80656a;95=#8c7683;96=#98889d;97=#a39bb8;98=#aeaed3;99=#b8c1ef;100=#938379;101=#9b908f;102=#a29ea6;103=#a9acbd;104=#b0bad4;105=#b5c8ec;106=#a5a288;107=#a9ab9b;108=#adb4ae;109=#afbdc1;110=#b1c6d5;111=#b3cfe8;112=#b7c297;113=#b7c6a7;114=#b6cab6;115=#b5cec6;116=#b3d2d5;117=#b0d7e5;118=#c9e3a7;119=#c5e2b3;120=#c0e1be;121=#bae0ca;122=#b4dfd6;123=#addee1;124=#985d74;125=#a46f8b;126=#af82a3;127=#ba95bc;128=#c5a9d5;129=#cfbdef;130=#a6777f;131=#af8694;132=#b695aa;133=#bea4c0;134=#c5b3d6;135=#cbc3ed;136=#b4928a;137=#b99c9d;138=#bda7b0;139=#c1b3c4;140=#c4bed8;141=#c6c9ec;142=#c1ac94;143=#c2b3a5;144=#c3bab6;145=#c3c1c7;146=#c3c8d9;147=#c2cfeb;148=#cdc79f;149=#cbcaae;150=#c9cdbc;151=#c6d0cb;152=#c2d2da;153=#bdd5e9;154=#dae3a9;155=#d4e1b6;156=#cee0c3;157=#c8decf;158=#c0dddb;159=#b8dbe8;160=#c5748e;161=#cc83a0;162=#d292b2;163=#d8a1c5;164=#ddb0d8;165=#e2bfeb;166=#cd8a94;167=#d196a5;168=#d5a1b6;169=#d8adc8;170=#dbb9d9;171=#ddc5eb;172=#d5a09a;173=#d6a8aa;174=#d7b1ba;175=#d8b9cb;176=#d7c1db;177=#d7caec;178=#dcb6a0;179=#dbbbaf;180=#d9c0bf;181=#d7c5ce;182=#d4cadd;183=#d0cfed;184=#e3cca6;185=#dfceb5;186=#dbcfc3;187=#d6d1d1;188=#d0d2df;189=#cad4ed;190=#eae3ac;191=#e3e1ba;192=#dcdec7;193=#d5dcd4;194=#ccdbe1;195=#c3d9ee;196=#f38ba8;197=#f496b4;198=#f5a1c1;199=#f6accd;200=#f5b7da;201=#f5c2e7;202=#f59daa;203=#f5a6b6;204=#f4aec3;205=#f2b6d0;206=#f0bedd;207=#eec6ea;208=#f7afab;209=#f5b4b8;210=#f2bac5;211=#eebfd2;212=#ebc5df;213=#e6caec;214=#f8c0ad;215=#f4c3ba;216=#f0c6c7;217=#eac9d4;218=#e5cbe1;219=#deceef;220=#f9d1ae;221=#f3d1bb;222=#edd1c9;223=#e6d2d6;224=#ded2e4;225=#d6d2f1;226=#f9e2af;227=#f2dfbd;228=#eaddcb;229=#e1dbd9;230=#d8d8e6;231=#cdd6f4;232=#242435;233=#2a2a3c;234=#303143;235=#36374a;236=#3d3e51;237=#434558;238=#4a4b60;239=#505267;240=#575a6f;241=#5e6177;242=#65687e;243=#6c6f86;244=#73778e;245=#7a7e96;246=#81869f;247=#888ea7;248=#9095af;249=#979db7;250=#9fa5c0;251=#a6adc8;252=#aeb5d1;253=#b6bdda;254=#bdc5e2;255=#c5ceeb;foreground=#cdd6f4;background=#1e1e2e;selection_foreground=#1e1e2e;selection_background=#f5e0dc;cursor=#f5e0dc;cursor_text=#1e1e2e\e\\"

class ThemeFilter
  TRIGGER = "\e[=997;".to_slice

  enum Theme
    Dark
    Light
  end

  @pos  = 0
  @mode = 0_u8

  def feed(chunk : Bytes, sink : IO, & : Theme ->) : Nil
    chunk.each do |byte|
      if @pos < TRIGGER.size
        if byte == TRIGGER[@pos]
          @pos += 1
        else
          sink.write TRIGGER[0, @pos]
          if byte == TRIGGER[0]
            @pos = 1
          else
            @pos = 0
            sink.write_byte byte
          end
        end
      elsif @pos == TRIGGER.size
        @mode = byte
        @pos += 1
      else
        if byte == 'n'.ord.to_u8 && (@mode == '1'.ord.to_u8 || @mode == '2'.ord.to_u8)
          yield @mode == '1'.ord.to_u8 ? Theme::Dark : Theme::Light
        else
          sink.write TRIGGER
          sink.write_byte @mode
          sink.write_byte byte
        end
        @pos = 0
      end
    end
  end
end

shell = ENV["SHELL"]? || "/bin/sh"
size  = TTY::Winsize.from(STDIN) || TTY::Pty::DEFAULT_SIZE

pty    = TTY::Pty.new(shell, ["-i"], size: size)
raw    = TTY::RawMode.new(STDIN)
filter = ThemeFilter.new

STDERR.print "\r\n\e[1;33m[demo] write \e[=997;1n for dark, " \
             "\e[=997;2n for light (needs OSC 21 support, e.g. kitty).\e[0m\r\n"
STDERR.flush

Signal::WINCH.trap do
  if current = TTY::Winsize.from(STDIN)
    pty.resize(current) rescue nil
  end
end

done = Channel(Nil).new

spawn do
  buffer = Bytes.new(4096)
  loop do
    n = pty.master.read(buffer)
    break if n.zero?
    filter.feed(buffer[0, n], STDOUT) do |theme|
      STDOUT.write(theme.dark? ? DARK.to_slice : LIGHT.to_slice)
    end
    STDOUT.flush
  end
rescue IO::Error
ensure
  done.send nil
end

spawn do
  buffer = Bytes.new(4096)
  loop do
    n = STDIN.read(buffer)
    break if n.zero?
    pty.write buffer[0, n]
  end
rescue IO::Error
ensure
  done.send nil
end

done.receive
pty.kill
code = pty.reap
raw.restore

STDOUT.flush
STDERR.puts "\r\n[demo] child exited with #{code.inspect}"
