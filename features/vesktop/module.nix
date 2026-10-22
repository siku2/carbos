{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.vesktop;
  json = pkgs.formats.json { };

  # Null keeps Vesktop's value.
  setting =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };

  prune = lib.filterAttrsRecursive (_: value: value != null);

  vesktop = json.generate "vesktop-settings.json" (prune {
    inherit (cfg)
      discordBranch
      minimizeToTray
      arRPC
      hardwareVideoAcceleration
      enableSplashScreen
      ;
  });

  plugins =
    lib.mapAttrs (_: plugin: { enabled = plugin.enable; }) cfg.plugins
    // lib.optionalAttrs (cfg.inputProfile != null) {
      InputProfile = {
        enabled = true;
        profile = cfg.inputProfile;
      };
    };

  vencord =
    pkgs.runCommand "vencord-settings.json"
      {
        nativeBuildInputs = [ pkgs.jq ];
        declared = builtins.toJSON {
          inherit plugins;
          enabledThemes = cfg.themes;
        };
        passAsFile = [ "declared" ];
      }
      ''
        unknown=$(jq -r --slurpfile catalog ${pkgs.vencord.catalog} \
          '.plugins | keys - [$catalog[0][].name] | join(", ")' "$declaredPath")
        if [ -n "$unknown" ]; then
          echo "Vencord has no plugins named $unknown" >&2
          exit 1
        fi
        cp "$declaredPath" $out
      '';
in
{
  options.carbos.vesktop = {
    package = lib.mkPackageOption pkgs "vesktop" { };

    discordBranch = setting (types.enum [
      "stable"
      "canary"
      "ptb"
    ]) "The Discord release to load.";
    minimizeToTray = setting types.bool "Keep running in the tray when the window closes.";
    arRPC = setting types.bool "Show the games you play as rich presence.";
    hardwareVideoAcceleration = setting types.bool "Decode and encode video on the GPU.";
    enableSplashScreen = setting types.bool "Show a splash window while Discord loads.";

    plugins = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options.enable = mkOption {
              type = types.bool;
              description = "Whether to turn on the ${name} plugin.";
            };
          }
        )
      );
      default = { };
      description = ''
        Vencord plugins by name. Plugins not listed here keep Vencord's
        default. Unknown names fail the build.
      '';
    };

    themes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Files in Vesktop's themes folder to turn on.";
    };

    inputProfile = setting (types.enum [
      "VOICE_ISOLATION"
      "STUDIO"
      "CUSTOM"
    ]) "The microphone input profile Discord switches to at startup.";
  };

  config = {
    # Vencord comes from our overlay with the local plugins.
    home.packages = [ (cfg.package.override { withSystemVencord = true; }) ];

    # Read-only on purpose. Changes made in the app last until it restarts.
    xdg.configFile = {
      "vesktop/settings.json" = {
        source = vesktop;
        force = true;
      };
      "vesktop/settings/settings.json" = {
        source = vencord;
        force = true;
      };
    };
  };
}
