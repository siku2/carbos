{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.cooling;
  yaml = pkgs.formats.yaml { };

  hwmon = {
    platform = mkOption {
      type = types.str;
      description = "Regex for the platform shown by `fan2go detect`.";
    };
    channel = mkOption {
      type = types.ints.positive;
      description = "Channel number, as in temp<N>_input or fan<N>_input.";
    };
  };

  pwm = mkOption {
    type = types.ints.between 0 255;
  };

  sensor.options = hwmon;

  curve.options = {
    sensor = mkOption {
      type = types.str;
      description = "Name of a sensor in carbos.cooling.sensors.";
    };
    steps = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            temp = mkOption { type = types.int; };
            speed = mkOption {
              type = types.ints.between 0 100;
              description = "Percent of the range from minPwm to maxPwm.";
            };
          };
        }
      );
    };
  };

  fan.options = hwmon // {
    curve = mkOption {
      type = types.str;
      description = "Name of a curve in carbos.cooling.curves.";
    };
    minPwm = pwm // {
      description = "Duty at 0%. The fan never stops below it.";
    };
    maxPwm = pwm // {
      default = 255;
      description = "Duty at 100%.";
    };
  };

  settings = {
    dbPath = "/var/lib/fan2go/fan2go.db";

    sensors = lib.mapAttrsToList (id: sensor: {
      inherit id;
      hwmon = { inherit (sensor) platform channel; };
    }) cfg.sensors;

    curves = lib.mapAttrsToList (id: curve: {
      inherit id;
      linear = {
        inherit (curve) sensor;
        steps = map (step: { ${toString step.temp} = "${toString step.speed}%"; }) curve.steps;
      };
    }) cfg.curves;

    fans = lib.mapAttrsToList (id: fan: {
      inherit id;
      inherit (fan) curve minPwm maxPwm;
      hwmon = {
        inherit (fan) platform;
        rpmChannel = fan.channel;
        pwmChannel = fan.channel;
      };
      neverStop = true;
      # The hub drivers report back the duty they were given.
      pwmMap = "identity";
      setPwmToGetPwmMap = "identity";
    }) cfg.fans;
  };

  configFile = yaml.generate "fan2go.yaml" settings;
in
{
  options.carbos.cooling = {
    sensors = mkOption {
      type = types.attrsOf (types.submodule sensor);
      default = { };
    };

    curves = mkOption {
      type = types.attrsOf (types.submodule curve);
      default = { };
    };

    fans = mkOption {
      type = types.attrsOf (types.submodule fan);
      default = { };
    };
  };

  config = lib.mkIf (cfg.fans != { }) {
    environment.etc."fan2go/fan2go.yaml".source = configFile;

    systemd.services.fan2go = {
      description = "fan2go fan control";
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ configFile ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.fan2go} -c /etc/fan2go/fan2go.yaml --no-style";
        Restart = "always";
        RestartSec = 10;
        StateDirectory = "fan2go";
      };
    };
  };
}
