{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.carbos.secureBoot;
in
{
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];

  options.carbos.secureBoot = {
    enable = lib.mkEnableOption "Secure Boot via lanzaboote";

    pkiBundle = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sbctl";
      description = ''
        Where sbctl keeps the signing keys. Run `sbctl create-keys` before
        turning this on, otherwise there is nothing to sign the boot files
        with and the system will not boot.
      '';
    };
  };

  config = lib.mkMerge [
    # sbctl is needed to create and enroll the keys, which has to happen
    # before this module can be enabled.
    { environment.systemPackages = [ pkgs.sbctl ]; }

    (lib.mkIf cfg.enable {
      # lanzaboote installs its own signed stub in place of systemd-boot.
      boot.loader.systemd-boot.enable = lib.mkForce false;

      boot.lanzaboote = {
        enable = true;
        inherit (cfg) pkiBundle;
      };
    })
  ];
}
