{
  flake.modules.nixos.shell = ./nixos.nix;

  flake.modules.homeManager.shell.imports = [
    ./atuin.nix
    ./cli.nix
    ./fish.nix
    ./starship.nix
  ];
}
