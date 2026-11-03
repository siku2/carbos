{ inputs, ... }:
{
  flake.modules.nixos.base = {
    imports = [
      ./system.nix
      ./user.nix
      ./vm.nix
    ]
    ++ (with inputs.self.modules.nixos; [
      agents
      git
      nix
      rust
      shell
      zed
    ]);
  };

  flake.modules.homeManager.base = ./home.nix;
}
