{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.ardour;
  json = pkgs.formats.json { };

  major = lib.versions.major cfg.package.version;
  configDir = "${config.xdg.configHome}/ardour${major}";

  # Each option is a key in one of Ardour's config files. Null keeps Ardour's.
  setting =
    type: description:
    mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };

  prune = lib.filterAttrsRecursive (_: value: value != null && value != { });

  files = prune {
    config.Config = {
      default-session-parent-dir = cfg.general.sessionDir;
      clip-library-dir = cfg.general.clipLibraryDir;
      plugin-path-lxvst = "${plugins}/lib/vst";
      plugin-path-vst3 = "${plugins}/lib/vst3";
    };
    ui_config.UI = {
      # Ardour stores it in 1/1024 percent.
      font-scale =
        if cfg.appearance.fontScale == null then null else toString (cfg.appearance.fontScale * 1024);
    };
  };

  plugins = pkgs.buildEnv {
    name = "ardour-plugins";
    paths = cfg.plugins;
    pathsToLink = [
      "/lib/lv2"
      "/lib/vst"
      "/lib/vst3"
    ];
  };

  # The JACK library comes from PipeWire even in sessions that started
  # before the system enabled it.
  package = pkgs.symlinkJoin {
    name = "ardour-${cfg.package.version}";
    paths = [ cfg.package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/ardour${major} \
        --prefix LD_LIBRARY_PATH : ${lib.getLib pkgs.pipewire.jack}/lib \
        --set LV2_PATH ${plugins}/lib/lv2
    '';
  };

  merge = pkgs.writeShellApplication {
    name = "ardour-settings";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.jq
      pkgs.xmlstarlet
    ];
    text = builtins.readFile ./settings.sh;
  };
in
{
  options.carbos.ardour = {
    package = lib.mkPackageOption pkgs "ardour" { };

    plugins = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = "LV2, VST and VST3 plugins Ardour can load.";
    };

    general = {
      sessionDir = setting types.str "The folder new sessions go in.";
      clipLibraryDir = setting types.str "The folder clips are added to.";
    };

    appearance.fontScale = setting types.ints.positive ''
      GUI and font scaling in percent. The first-run wizard guesses it from
      the display.
    '';
  };

  config = {
    home.packages = [ package ];

    # Skips the first-run wizard. Its choices are the options above.
    xdg.configFile."ardour${major}/.a${major}".text = "";

    # Ardour rewrites its config files, so the options are merged in on every
    # switch instead of owning the files. Ardour saves over them when it quits.
    home.activation.ardourSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      DIR=${lib.escapeShellArg configDir} \
      SETTINGS=${json.generate "ardour-settings.json" files} \
      run ${lib.getExe merge}
    '';
  };
}
