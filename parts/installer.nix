{
  config,
  inputs,
  lib,
  ...
}:
let
  inherit (inputs) self;

  # An installer only carries the hosts of its own platform.
  bundleFor = system: {
    source = "${self}";
    repo = "https://github.com/siku2/carbos.git";
    rev = self.shortRev or self.dirtyShortRev or "unknown";
    hosts = import ../installer/bundle.nix {
      inherit lib;
      configurations = lib.filterAttrs (
        _: host: host.config.nixpkgs.hostPlatform.system == system
      ) config.flake.nixosConfigurations;
    };
  };
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      bundle = bundleFor system;
    in
    lib.mkIf pkgs.stdenv.isLinux {
      packages = {
        carbos-install = pkgs.callPackage ../installer/package.nix { inherit bundle; };

        kexec-installer = pkgs.callPackage ../installer/kexec.nix {
          installer = inputs.nixpkgs.lib.nixosSystem {
            modules = [
              ../installer
              {
                nixpkgs.hostPlatform = system;
                carbos.installer.bundle = bundle;
              }
            ];
          };
        };
      };

      checks.installer = pkgs.testers.runNixOSTest (import ../installer/test.nix { inherit inputs; });
    };
}
