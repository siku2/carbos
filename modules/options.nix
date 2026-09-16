{
  lib,
  pkgs,
  ...
}:
{
  options.carbos = {
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
