{ inputs, lib, ... }:
let
  hosts = builtins.attrNames (builtins.readDir ../hosts);
in
{
  # Each host pulls in whatever extra modules it needs itself.
  flake.nixosConfigurations = lib.genAttrs hosts (
    name:
    inputs.nixpkgs.lib.nixosSystem {
      specialArgs = {
        inherit inputs;
      };
      modules = [
        ../hosts/${name}
        inputs.disko.nixosModules.disko
        inputs.home-manager.nixosModules.home-manager
      ];
    }
  );
}
