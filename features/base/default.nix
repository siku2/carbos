{ inputs, ... }:
{
  flake.modules.nixos.base = {
    imports = [
      ./system.nix
      ./unfree.nix
      ./user.nix
      ./vm.nix
    ]
    ++ (with inputs.self.modules.nixos; [
      agents
      direnv
      git
      packages
      rust
      shell
      zed
    ]);
  };

  flake.modules.homeManager.base = ./home.nix;
}
