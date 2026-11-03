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
      dev
      git
      nix
      shell
    ]);
  };

  flake.modules.homeManager.base = ./home.nix;
}
