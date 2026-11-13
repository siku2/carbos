{
  config,
  lib,
  ...
}:
let
  cfg = config.carbos.ccache;
  inherit (config.programs.ccache) cacheDir;

  conf = lib.generators.toKeyValue { } {
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

    # A real file, since a store symlink dangles inside the build sandbox.
    systemd.tmpfiles.settings.ccache."${cacheDir}/ccache.conf"."f+" = {
      mode = "0644";
      argument = conf;
    };
  };
}
