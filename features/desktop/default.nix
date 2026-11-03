{ inputs, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [
      ./default-apps.nix
      ./dms/nixos.nix
      ./font-options.nix
      ./fonts.nix
      ./niri/nixos.nix
      ./nixos.nix
    ]
    ++ (with inputs.self.modules.nixos; [
      bitwarden
      cloud
      firefox
      fractal
      kicad
      rbw
      secretspec
    ]);
  };

  flake.modules.homeManager.desktop.imports = [
    ./dms/home.nix
    ./dsearch.nix
    ./home.nix
    ./niri/home.nix
    ./wallpaper/home.nix
  ];
}
