{
  flake.modules.nixos.user.imports = [
    ./nixos.nix
    ./system.nix
  ];

  flake.modules.darwin.user.imports = [
    ./darwin.nix
    ./system.nix
  ];

  flake.modules.homeManager.user = ./home.nix;
}
