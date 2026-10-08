{ inputs, lib, ... }:
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
    "aarch64-darwin"
  ];

  # Darwin tracks its own nixpkgs branch for binary cache coverage.
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs =
        (if lib.hasSuffix "-darwin" system then inputs.nixpkgs-darwin else inputs.nixpkgs)
        .legacyPackages.${system};
    };
}
