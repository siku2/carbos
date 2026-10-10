{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.mic;

  # Field names and units follow Easy Effects presets, so values can be copied
  # over from its UI.
  option =
    type: description:
    mkOption {
      inherit type description;
    };

  db = description: option types.float "${description} in dB.";
  ms = description: option types.float "${description} in ms.";

  plugin = options: mkOption { type = types.submodule { inherit options; }; };

  # In the order of the LSP enum values.
  enums = {
    filterType = [
      "Lo-pass"
      "Hi-pass"
      "Lo-shelf"
      "Hi-shelf"
      "Bell"
      "Bandpass"
      "Notch"
      "Resonance"
      "Ladder-pass"
      "Ladder-rej"
      "Allpass"
    ];
    slope = [
      "x1"
      "x2"
      "x3"
      "x4"
      "x6"
      "x8"
      "x12"
      "x16"
    ];
    sidechainMode = [
      "Peak"
      "RMS"
      "LPF"
      "SMA"
    ];
  };

  plugins = {
    filter = plugin {
      type = option (types.enum enums.filterType) "Filter type.";
      slope = option (types.enum enums.slope) "Filter slope.";
      frequency = option types.float "Frequency in Hz.";
      gain = db "Gain";
      quality = option types.float "Quality factor on the LSP scale.";
    };

    deepfilternet = plugin {
      attenuation-limit = db "Most noise reduction";
      min-processing-threshold = db "SNR below which only noise is attenuated";
      max-erb-processing-threshold = db "SNR above which the ERB stage is skipped";
      max-df-processing-threshold = db "SNR above which the DF stage is skipped";
    };

    gate = plugin {
      attack = ms "Attack";
      release = ms "Release";
      curve-threshold = db "Threshold";
      curve-zone = db "Zone size";
      hysteresis = option types.bool "Whether the gate closes at a lower threshold.";
      hysteresis-threshold = db "Hysteresis threshold relative to the threshold";
      hysteresis-zone = db "Hysteresis zone size";
      reduction = db "Gain reduction while closed";
      sidechain = {
        mode = option (types.enum enums.sidechainMode) "Sidechain detection.";
        lookahead = ms "Sidechain lookahead";
        reactivity = ms "Sidechain reactivity";
      };
    };

    limiter = plugin {
      threshold = db "Threshold";
      attack = ms "Attack";
      release = ms "Release";
      lookahead = ms "Lookahead";
      alr = option types.bool "Whether automatic level regulation is on.";
      gain-boost = option types.bool "Whether the output is raised to the threshold.";
    };
  };

  graph = import ./filter-chain.nix {
    inherit lib pkgs enums;
    inherit (inputs.self.lib) math;
  } cfg.plugins;

  conf = pkgs.writeText "mic.conf" (
    builtins.toJSON {
      "context.spa-libs" = {
        "audio.convert.*" = "audioconvert/libspa-audioconvert";
        "support.*" = "support/libspa-support";
      };
      "context.modules" = [
        {
          name = "libpipewire-module-rt";
          flags = [
            "ifexists"
            "nofail"
          ];
        }
        { name = "libpipewire-module-protocol-native"; }
        { name = "libpipewire-module-client-node"; }
        { name = "libpipewire-module-adapter"; }
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = cfg.name;
            "media.name" = cfg.name;
            "filter.graph" = graph;
            "capture.props" = {
              "node.name" = "mic_input";
              "audio.position" = [ "MONO" ];
              "target.object" = cfg.device;
              # Only run while something records.
              "node.passive" = true;
              # The fallback would be this chain itself.
              "node.dont-fallback" = true;
            };
            "playback.props" = {
              "node.name" = "mic";
              "media.class" = "Audio/Source";
              "audio.position" = [ "MONO" ];
              "priority.session" = cfg.priority;
            };
          };
        }
      ];
    }
  );
in
{
  options.carbos.mic = {
    enable = lib.mkEnableOption "a processed microphone source";

    name = option types.str "Name of the processed source.";

    device = option types.str "Node name of the raw microphone.";

    priority = mkOption {
      type = types.int;
      default = 10000;
      description = "Session priority. Above every hardware source, so it becomes the default.";
    };

    plugins = mkOption {
      type = types.listOf (types.attrTag plugins);
      description = "Plugins in processing order.";
    };
  };

  config = lib.mkIf cfg.enable {
    # A separate client, so a change restarts the chain and not all of PipeWire.
    systemd.user.services.mic = {
      Unit = {
        Description = cfg.name;
        After = [ "pipewire.service" ];
        PartOf = [ "pipewire.service" ];
      };
      Service.ExecStart = "${lib.getExe' pkgs.pipewire "pipewire"} -c ${conf}";
      Install.WantedBy = [ "default.target" ];
    };
  };
}
