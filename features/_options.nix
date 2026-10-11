{ config, lib, ... }:
{
  options.carbos.user = {
    fullName = lib.mkOption {
      type = lib.types.str;
    };

    email = lib.mkOption {
      type = lib.types.str;
    };

    projectsDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/Projects";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/Projects"'';
      description = "Directory that holds the project checkouts.";
    };
  };
}
