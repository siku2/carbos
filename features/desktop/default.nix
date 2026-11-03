{
  flake.modules.nixos.desktop.imports = [
    ./audio.nix
    ./default-apps.nix
    ./dms/nixos.nix
    ./fonts.nix
    ./niri/nixos.nix
    ./nixos.nix
  ];

  flake.modules.homeManager.desktop.imports = [
    ./dms/home.nix
    ./dsearch.nix
    ./home.nix
    ./niri/home.nix
    ./wallpaper/home.nix
  ];
}
