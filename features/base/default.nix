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
      claude-code
      cli
      codex
      direnv
      gh
      git
      packages
      rust
      starship
      zed
    ]);
  };

  flake.modules.homeManager.base = ./home.nix;
}
