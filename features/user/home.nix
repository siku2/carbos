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

    signing = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            format = lib.mkOption {
              type = lib.types.enum [
                "ssh"
                "openpgp"
              ];
            };

            key = lib.mkOption {
              type = lib.types.str;
              description = "Public SSH key, or the fingerprint of the OpenPGP key.";
            };
          };
        }
      );
      default = null;
      description = "Key that signs commits and tags.";
    };
  };

  config = {
    # Generating it pulls in an options.json derivation that nix warns about.
    manual.manpages.enable = false;

    programs.home-manager.enable = true;
  };
}
