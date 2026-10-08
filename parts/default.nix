{
  imports = [
    ./devshell.nix
    ./features.nix
    ./hosts.nix
    ./installer.nix
    ./treefmt.nix
  ];

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
