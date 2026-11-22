{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.plotter;

  inx = pkgs.replaceVars ./fenta_plot.inx { inherit (cfg) port; };
in
{
  options.carbos.plotter.port = mkOption {
    type = types.nullOr types.str;
    default = null;
    description = "Serial device of the Fenta cutter.";
  };

  config = lib.mkIf (cfg.port != null) {
    xdg.configFile = {
      "inkscape/extensions/fenta_plot.inx".source = inx;
      "inkscape/extensions/fenta_plot.py".source = ./fenta_plot.py;
    };
  };
}
