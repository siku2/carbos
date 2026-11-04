{
  flake.modules.nixos.shell = ./system.nix;

  flake.modules.darwin.shell.imports = [
    ./darwin.nix
    ./system.nix
  ];

  flake.modules.homeManager.shell.imports = [
    ./atuin.nix
    ./cli.nix
    ./fish.nix
    ./starship.nix
  ];
}
