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
      bitwarden
      cloud
      dms
      dsearch
      firefox
      fractal
      kicad
      nextcloud
      niri
      opencode
      rbw
      secretspec
      wallpaper
    ]);
  };

  flake.modules.homeManager.desktop = ./home.nix;
}
