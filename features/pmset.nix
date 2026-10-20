{
  flake.modules.darwin.pmset =
    { config, lib, ... }:
    let
      cfg = config.pmset;

      settingsType =
        with lib.types;
        attrsOf (oneOf [
          bool
          int
          str
        ]);

      toValue = value: if lib.isBool value then (if value then "1" else "0") else toString value;

      apply =
        flag: settings:
        lib.optionalString (settings != { }) ''
          /usr/bin/pmset ${flag} ${
            lib.concatStringsSep " " (
              lib.mapAttrsToList (name: value: "${name} ${lib.escapeShellArg (toValue value)}") settings
            )
          }
        '';
    in
    {
      options.pmset = {
        enable = lib.mkEnableOption "managing all pmset settings. Anything not declared is reset to the macOS default on activation";

        all = lib.mkOption {
          type = settingsType;
          default = { };
          description = "Settings for every power source (`pmset -a`).";
        };

        ac = lib.mkOption {
          type = settingsType;
          default = { };
          description = "Settings for AC power (`pmset -c`).";
        };

        battery = lib.mkOption {
          type = settingsType;
          default = { };
          description = "Settings for battery power (`pmset -b`).";
        };
      };

      config = lib.mkIf cfg.enable {
        system.activationScripts.postActivation.text = ''
          /usr/bin/pmset restoredefaults >/dev/null
          ${apply "-a" cfg.all}
          ${apply "-c" cfg.ac}
          ${apply "-b" cfg.battery}
        '';
      };
    };
}
