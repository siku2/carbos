{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.carbos.ccache;
  inherit (config.programs.ccache) cacheDir;

  conf = (pkgs.formats.keyValue { }).generate "ccache.conf" {
    max_size = cfg.maxSize;
  };
in
{
  options.carbos.ccache.maxSize = lib.mkOption {
    type = lib.types.strMatching "[0-9]+[kMGT]i?";
    default = "100G";
    description = "Size limit of the shared ccache used by Nix builds.";
  };

  config = {
    programs.ccache.enable = true;

    nix.settings.extra-sandbox-paths = [ cacheDir ];

    systemd.tmpfiles.rules = [ "L+ ${cacheDir}/ccache.conf - - - - ${conf}" ];
  };
}
