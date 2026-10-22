{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.dms;
  json = pkgs.formats.json { };

  widget = types.either types.str (
    types.submodule {
      freeformType = json.type;
      options.id = mkOption { type = types.str; };
    }
  );

  widgets =
    side:
    mkOption {
      type = types.listOf widget;
      default = [ ];
      description = "Widgets on the ${side}, by id. Lists from several modules are joined.";
    };

  bar = types.submodule {
    options = {
      left = widgets "left";
      center = widgets "center";
      right = widgets "right";
      settings = mkOption {
        inherit (json) type;
        default = { };
        description = "Other keys of the bar. DMS's bar defaults fill in the rest.";
      };
    };
  };

  plugin = types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "the ${name} plugin";

        package = mkOption {
          type = types.package;
          default = pkgs.dms-plugins.${name};
          defaultText = lib.literalExpression "pkgs.dms-plugins.${name}";
          description = "Needs `passthru.manifest` to be usable in bars.";
        };

        settings = mkOption {
          inherit (json) type;
          default = { };
          description = "Stored next to the enabled flag in plugin_settings.json.";
        };
      };
    }
  );

  enabled = lib.filterAttrs (_: plugin: plugin.enable) cfg.plugins;

  settingsFile = pkgs.callPackage ./settings.nix {
    dms = osConfig.programs.dms-shell.package;
    declared = {
      inherit (cfg) settings bars;
      pluginWidgets = lib.attrNames (
        lib.filterAttrs (
          _: plugin: lib.elem "dankbar-widget" (plugin.package.manifest.capabilities or [ ])
        ) enabled
      );
    };
  };

  pluginSettingsFile = json.generate "dms-plugin-settings.json" (
    lib.mapAttrs (_: plugin: { enabled = true; } // plugin.settings) enabled
  );
  files = {
    "settings.json" = settingsFile;
    "plugin_settings.json" = pluginSettingsFile;
  }
  // lib.mapAttrs' (name: plugin: lib.nameValuePair "plugins/${name}" plugin.package) enabled;

  # One store path that changes with any of the files.
  bundle = pkgs.linkFarm "dms-config" files;

  restart = pkgs.writeShellApplication {
    name = "dms-restart";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
    ];
    text = builtins.readFile ./restart.sh;
  };
in
{
  options.carbos.dms = {
    settings = mkOption {
      inherit (json) type;
      default = { };
      description = "Settings that differ from DMS's defaults. Unknown keys fail the build.";
    };

    bars = mkOption {
      type = types.attrsOf bar;
      default = { };
      description = "Bars by id.";
    };

    plugins = mkOption {
      type = types.attrsOf plugin;
      default = { };
      description = "Plugins by id. Enabled ones are installed, switched on and usable in bars.";
    };
  };

  config = {
    # Read-only on purpose. DMS keeps changes made in its settings until it
    # restarts and offers to copy them.
    xdg.configFile = lib.mapAttrs' (
      path: source:
      lib.nameValuePair "DankMaterialShell/${path}" {
        inherit source;
        force = true;
      }
    ) files;

    home.activation.dmsRestart = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
      STAMP=${lib.escapeShellArg "${config.xdg.stateHome}/carbos/dms-config"} \
      CONFIG=${bundle} \
      QML_CACHE=${lib.escapeShellArg "${config.xdg.cacheHome}/quickshell/qmlcache"} \
      run ${lib.getExe restart}
    '';
  };
}
