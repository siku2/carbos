{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.kicad;
  json = pkgs.formats.json { };

  # Each option is a key in one of KiCad's settings files. Null keeps KiCad's.
  setting =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };

  canvasTypes = {
    opengl = 1;
    cairo = 2;
  };

  antialiasingModes = {
    none = 0;
    fast = 1;
    high-quality = 2;
  };

  lookup = table: value: if value == null then null else table.${value};

  prune = lib.filterAttrsRecursive (_: value: value != null && value != { });

  files = prune {
    kicad_common.graphics = prune {
      canvas_type = lookup canvasTypes cfg.graphics.canvas;
      antialiasing_mode = lookup antialiasingModes cfg.graphics.antialiasing;
    };
  };

  merge = pkgs.writeShellApplication {
    name = "kicad-settings";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./settings.sh;
  };
in
{
  options.carbos.kicad = {
    package = lib.mkPackageOption pkgs "kicad" { };

    graphics = {
      canvas = setting (types.enum (lib.attrNames canvasTypes)) ''
        The renderer. KiCad saves Cairo after OpenGL fails once.
      '';
      antialiasing = setting (types.enum (lib.attrNames antialiasingModes)) ''
        Antialiasing for the OpenGL renderer.
      '';
    };
  };

  config = {
    home.packages = [ cfg.package ];

    # KiCad rewrites its settings files, so the keys are merged in on every
    # switch instead of owning the files.
    home.activation.kicadSettings = lib.mkIf (files != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        DIR=${lib.escapeShellArg "${config.xdg.configHome}/kicad/${lib.versions.majorMinor cfg.package.version}"} \
        SETTINGS=${json.generate "kicad-settings.json" files} \
        run ${lib.getExe merge}
      ''
    );
  };
}
