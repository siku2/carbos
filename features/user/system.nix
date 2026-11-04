{
  config,
  inputs,
  lib,
  ...
}:
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
}
