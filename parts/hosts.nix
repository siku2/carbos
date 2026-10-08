{ inputs, lib, ... }:
let
  hostsIn = dir: builtins.attrNames (builtins.readDir dir);
in
{
  # Each host pulls in whatever extra modules it needs itself.
  flake.nixosConfigurations = lib.genAttrs (hostsIn ../hosts/nixos) (
    name:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
      };
      modules = [
        ../hosts/nixos/${name}
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.home-manager
      ];
    }
  );
}
