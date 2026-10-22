{ inputs, ... }:
let
  system =
    { config, lib, ... }:
    let
      cfg = config.carbos.user;
    in
    {
      options.carbos.user = {
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

      config.home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit inputs; };
        users.${cfg.login}.carbos.user = { inherit (cfg) fullName email; };
      };
    };
in
{
  flake.modules.nixos.user = system;
  flake.modules.darwin.user = system;

  flake.modules.homeManager.user =
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
    };
}
