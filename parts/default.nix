{
  imports = [
    ./devshell.nix
    ./hosts.nix
    ./installer.nix
    ./treefmt.nix
  ];

  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
}
