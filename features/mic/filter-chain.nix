{
  lib,
  pkgs,
  math,
  enums,
}:
plugins:
let
  # LSP takes gains as linear factors.
  gain = db: math.exp (db * 2.302585092994046 / 20);

  index = list: value: lib.lists.findFirstIndex (item: item == value) null list;

  lsp = name: {
    type = "ladspa";
    plugin = "${pkgs.lsp-plugins}/lib/ladspa/lsp-plugins-ladspa.so";
    label = "http://lsp-plug.in/plugins/ladspa/${name}";
    input = "Input";
    output = "Output";
  };

  render = {
    filter =
      p:
      lsp "filter_mono"
      // {
        control = {
          "Filter type" = index enums.filterType p.type;
          "Filter slope" = index enums.slope p.slope;
          "Frequency (Hz)" = p.frequency;
          "Gain (G)" = gain p.gain;
          "Quality factor" = p.quality;
        };
      };

    deepfilternet = p: {
      type = "ladspa";
      plugin = "${pkgs.deepfilternet}/lib/ladspa/libdeep_filter_ladspa.so";
      label = "deep_filter_mono";
      input = "Audio In";
      output = "Audio Out";
      control = {
        "Attenuation Limit (dB)" = p.attenuation-limit;
        "Min processing threshold (dB)" = p.min-processing-threshold;
        "Max ERB processing threshold (dB)" = p.max-erb-processing-threshold;
        "Max DF processing threshold (dB)" = p.max-df-processing-threshold;
      };
    };

    gate =
      p:
      lsp "gate_mono"
      // {
        control = {
          "Attack (ms)" = p.attack;
          "Release (ms)" = p.release;
          "Curve threshold (G)" = gain p.curve-threshold;
          "Curve zone size (G)" = gain p.curve-zone;
          "Hysteresis" = if p.hysteresis then 1 else 0;
          "Hysteresis threshold (G)" = gain p.hysteresis-threshold;
          "Hysteresis zone size (G)" = gain p.hysteresis-zone;
          "Reduction (G)" = gain p.reduction;
          "Sidechain mode" = index enums.sidechainMode p.sidechain.mode;
          "Sidechain lookahead (ms)" = p.sidechain.lookahead;
          "Sidechain reactivity (ms)" = p.sidechain.reactivity;
        };
      };

    limiter =
      p:
      lsp "limiter_mono"
      // {
        control = {
          "Threshold (G)" = gain p.threshold;
          "Attack time (ms)" = p.attack;
          "Release time (ms)" = p.release;
          "Lookahead (ms)" = p.lookahead;
          "Automatic level regulation" = if p.alr then 1 else 0;
          "Gain boost" = if p.gain-boost then 1 else 0;
        };
      };
  };

  nodes = lib.imap0 (
    i: tagged:
    let
      kind = lib.head (lib.attrNames tagged);
    in
    render.${kind} tagged.${kind} // { name = "${kind}${toString i}"; }
  ) plugins;

  port = node: name: "${node.name}:${node.${name}}";
in
{
  nodes = map (
    node:
    removeAttrs node [
      "input"
      "output"
    ]
  ) nodes;
  links = lib.zipListsWith (from: to: {
    output = port from "output";
    input = port to "input";
  }) nodes (lib.tail nodes);
  inputs = [ (port (lib.head nodes) "input") ];
  outputs = [ (port (lib.last nodes) "output") ];
}
