{ lib, pkgs, ... }:
let
  # -80.01 dB is LSP's "off" for a routing slot.
  off = -80.01;

  routing = {
    input-to-link = off;
    input-to-sidechain = off;
    link-to-input = off;
    link-to-sidechain = off;
    sidechain-to-input = off;
    sidechain-to-link = off;
  };

  # Shared by the two LSP dynamics plugins, so only the tuned values appear below.
  dynamics = routing // {
    attack = 20.0;
    bypass = false;
    dry = off;
    hpf-frequency = 10.0;
    hpf-mode = "Off";
    input-gain = 0.0;
    lpf-frequency = 20000.0;
    lpf-mode = "Off";
    makeup = 0.0;
    output-gain = 0.0;
    release = 100.0;
    stereo-split = false;
    wet = 0.0;
    sidechain = {
      lookahead = 0.0;
      mode = "Peak";
      preamp = 0.0;
      reactivity = 10.0;
      source = "Middle";
      stereo-split-source = "Left/Right";
    };
  };
in
{
  services.easyeffects = {
    enable = true;

    extraPresets.mic.input = {
      blocklist = [ ];

      plugins_order = [
        "echo_canceller#0"
        "rnnoise#0"
        "gate#0"
        "compressor#1"
        "limiter#0"
      ];

      "echo_canceller#0" = {
        bypass = false;
        input-gain = 0.0;
        output-gain = 0.0;
        echo-canceller = {
          automatic-gain-control = false;
          enable = true;
          enforce-high-pass = false;
          mobile-mode = false;
        };
        high-pass = {
          enable = false;
          full-band = false;
        };
        noise-suppression = {
          enable = false;
          level = "Moderate";
        };
      };

      "rnnoise#0" = {
        bypass = false;
        enable-vad = true;
        input-gain = 0.0;
        model-name = ''""'';
        output-gain = 0.0;
        release = 20.0;
        use-standard-model = true;
        vad-thres = 50.0;
        wet = 0.0;
      };

      "gate#0" = lib.recursiveUpdate dynamics {
        curve-threshold = -30.0;
        curve-zone = -6.0;
        hysteresis = false;
        hysteresis-threshold = -12.0;
        hysteresis-zone = -6.0;
        reduction = -24.0;
        sidechain.type = "Internal";
      };

      "compressor#1" = lib.recursiveUpdate dynamics {
        boost-amount = 6.0;
        boost-threshold = -72.0;
        knee = -6.0;
        mode = "Downward";
        ratio = 4.0;
        release-threshold = off;
        threshold = -12.0;
        sidechain.type = "Feed-forward";
      };

      "limiter#0" = routing // {
        alr = false;
        alr-attack = 5.0;
        alr-knee = 0.0;
        alr-knee-smooth = -5.0;
        alr-release = 50.0;
        attack = 5.0;
        bypass = false;
        dithering = "None";
        gain-boost = true;
        input-gain = 0.0;
        lookahead = 5.0;
        mode = "Herm Thin";
        output-gain = 0.0;
        oversampling = "None";
        release = 5.0;
        sidechain-preamp = 0.0;
        sidechain-type = "Internal";
        stereo-link = 100.0;
        threshold = 0.0;
      };
    };
  };

  # --load-preset only reaches an instance that is already running, so passing
  # it at service start does nothing. The fallback preset loads whenever the
  # input device is set, startup included.
  home.activation.easyeffectsFallbackPreset = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    let
      write = "run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file easyeffects/db/easyeffectsrc --group Window";
    in
    ''
      ${write} --key inputAutoloadingUsesFallback --type bool true
      ${write} --key inputAutoloadingFallbackPreset mic
    ''
  );
}
