{
  flake.modules.nixos.shell = ./system.nix;

  flake.modules.darwin.shell = {
    imports = [
      ./darwin.nix
      ./system.nix
    ];

    home-manager.sharedModules = [ ./home-darwin.nix ];
  };

  flake.modules.homeManager.shell.imports = [
    ./atuin.nix
    ./cli.nix
    ./fish.nix
    ./starship.nix
  ];
}
