{
  lib,
  pkgs,
  ...
}:
{
  options.carbos = {
    thinkpad = {
      biosSettings = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          AdaptiveThermalManagementAC = "MaximizePerformance";
        };
      };

      batteryChargeLimit = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 1 100);
        default = null;
        description = "Cap charging at the given percentage via udev to spare the battery.";
      };
    };

    user = {
      login = lib.mkOption {
        type = lib.types.str;
        default = "simon";
      };

      fullName = lib.mkOption {
        type = lib.types.str;
        default = "Simon Berger";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "simon@siku2.io";
      };
    };

    fonts = {
      mono = {
        package = lib.mkPackageOption pkgs [
          "nerd-fonts"
          "jetbrains-mono"
        ] { };

        name = lib.mkOption {
          type = lib.types.str;
          default = "JetBrainsMono Nerd Font";
        };

        size = lib.mkOption {
          type = lib.types.ints.positive;
          default = 11;
        };
      };
    };
  };
}
