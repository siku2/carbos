{ inputs, lib, ... }:
let
  hostsIn = dir: builtins.attrNames (builtins.readDir dir);
in
{
  # Each host pulls in whatever extra modules it needs itself.
  flake = {
    nixosConfigurations = lib.genAttrs (hostsIn ../hosts/nixos) (
      name:
      inputs.nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ../hosts/nixos/${name}
          inputs.self.modules.nixos.user
          inputs.disko.nixosModules.disko
          inputs.home-manager.nixosModules.home-manager
        ];
      }
    );

    darwinConfigurations = lib.genAttrs (hostsIn ../hosts/darwin) (
      name:
      inputs.nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit inputs;
        };
        modules = [
          ../hosts/darwin/${name}
          inputs.self.modules.darwin.user
          inputs.home-manager.darwinModules.home-manager
        ];
      }
    );
  };
}
