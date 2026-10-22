{
  lib,
  pkgs,
  ...
}:
{
  options.carbos = {
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
