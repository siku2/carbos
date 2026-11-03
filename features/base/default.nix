{ inputs, ... }:
{
  flake.modules.nixos.base = {
    imports = [
      ./system.nix
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
}
