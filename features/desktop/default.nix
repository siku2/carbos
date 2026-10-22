{ inputs, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [
      ./default-apps.nix
      ./font-options.nix
      ./fonts.nix
      ./nixos.nix
    ]
    ++ (with inputs.self.modules.nixos; [
      dms
      niri
    ]);
  };

  flake.modules.homeManager.desktop = ./home.nix;
}
