{
  flake.modules.homeManager.dev.imports = [
    ./go.nix
    ./home.nix
    ./rust.nix
    ./zed.nix
  ];
}
