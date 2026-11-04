{
  imports = [ ./packages ];

  flake.modules.nixos.nix.imports = [
    ./nixos.nix
    ./system.nix
  ];

  flake.modules.darwin.nix.imports = [
    ./darwin.nix
    ./system.nix
  ];

  flake.modules.homeManager.nix.imports = [
    ./direnv.nix
    ./home.nix
  ];
}
