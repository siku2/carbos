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
in
{
  services.easyeffects = {
    enable = true;

    extraPresets.mic.input = {
      # Easy Effects rejects a preset without it.
      blocklist = [ ];

      plugins_order = [
        "filter#0"
        "filter#1"
        "deepfilternet#0"
        "gate#0"
        "limiter#0"
      ];

      # Highway and fan rumble.
      "filter#0" = {
        balance = 0.0;
        bypass = false;
        equal-mode = "IIR";
        frequency = 100.0;
        gain = 0.0;
        input-gain = 0.0;
        mode = "RLC (BT)";
        output-gain = 0.0;
        quality = 0.0;
        slope = "x2";
        type = "High-pass";
        width = 4.0;
      };

      # Broad PC fan hum at 170-225 Hz. Q 4 spares the voice fundamental around 100 Hz.
      "filter#1" = {
        balance = 0.0;
        bypass = false;
        equal-mode = "IIR";
        frequency = 195.0;
        gain = -6.0;
        input-gain = 0.0;
        mode = "RLC (BT)";
        output-gain = 0.0;
        quality = 4.0;
        slope = "x1";
        type = "Bell";
        width = 4.0;
      };

      "deepfilternet#0" = {
        attenuation-limit = 25.0;
        bypass = false;
        input-gain = 0.0;
        max-df-processing-threshold = 20.0;
        max-erb-processing-threshold = 30.0;
        min-processing-buffer = 0;
        min-processing-threshold = -15.0;
        output-gain = 0.0;
        post-filter-beta = 0.0;
      };

      # Full gate. -72 dB is the LSP maximum and silences what DeepFilterNet leaves of the room.
      # The raw room sits at -55 dBFS and the quietest speech at about -42.
      "gate#0" = routing // {
        attack = 2.0;
        bypass = false;
        curve-threshold = -52.0;
        curve-zone = -6.0;
        dry = off;
        hpf-frequency = 10.0;
        hpf-mode = "Off";
        hysteresis = true;
        hysteresis-threshold = -3.0;
        hysteresis-zone = -3.0;
        input-gain = 0.0;
        lpf-frequency = 20000.0;
        lpf-mode = "Off";
        makeup = 0.0;
        output-gain = 0.0;
        reduction = -72.0;
        release = 200.0;
        stereo-split = false;
        wet = 0.0;
        sidechain = {
          lookahead = 5.0;
          mode = "RMS";
          preamp = 0.0;
          reactivity = 10.0;
          source = "Middle";
          stereo-split-source = "Left/Right";
          type = "Internal";
        };
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
        gain-boost = false;
        input-gain = 0.0;
        lookahead = 5.0;
        mode = "Herm Thin";
        output-gain = 0.0;
        oversampling = "None";
        release = 5.0;
        sidechain-preamp = 0.0;
        sidechain-type = "Internal";
        stereo-link = 100.0;
        threshold = -1.0;
      };
    };
  };

  # --load-preset only reaches an instance that is already running, so passing
  # it at service start does nothing. The fallback preset loads whenever the
  # input device is set, startup included.
  home.activation.easyeffectsSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    let
      write = "run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file easyeffects/db/easyeffectsrc";
    in
    ''
      ${write} --group Window --key inputAutoloadingUsesFallback --type bool true
      ${write} --group Window --key inputAutoloadingFallbackPreset mic
      ${write} --group StreamInputs --key listenToMic --type bool false
      ${write} --group EffectsPipelines --key processAllOutputs --type bool false
      ${write} --group EffectsPipelines --key processAllInputs --type bool false
    ''
  );

  # Apps get the processed mic as the default source instead of being moved to
  # it. Wireplumber falls back to the raw mic while Easy Effects is not running.
  systemd.user.services.easyeffects = {
    Unit = {
      After = [ "wireplumber.service" ];
      Wants = [ "wireplumber.service" ];
    };
    Service.ExecStartPost = "${pkgs.pipewire}/bin/pw-metadata 0 default.configured.audio.source '{\"name\":\"easyeffects_source\"}' Spa:String:JSON";
  };
}
