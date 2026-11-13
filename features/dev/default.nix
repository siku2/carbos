{
  flake.modules.nixos.dev.imports = [ ./ccache.nix ];

  flake.modules.homeManager.dev.imports = [
    ./go.nix
    ./home.nix
    ./rust.nix
    ./zed.nix
  ];
}
