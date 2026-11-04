{
  flake.modules.homeManager.dev.imports = [
    ./home.nix
    ./rust.nix
    ./zed.nix
  ];
}
