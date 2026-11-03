{
  flake.modules.homeManager.shell.imports = [
    ./atuin.nix
    ./cli.nix
    ./starship.nix
  ];
}
