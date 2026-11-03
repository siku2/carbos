{ inputs, ... }:
{
  flake.modules.nixos.desktop = {
    imports = [
      ./audio.nix
      ./default-apps.nix
      ./dms/nixos.nix
      ./font-options.nix
      ./fonts.nix
      ./niri/nixos.nix
      ./nixos.nix
    ]
    ++ (with inputs.self.modules.nixos; [
      cloud
      firefox
      fractal
      kicad
      vault
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
