{
  flake.modules.nixos.system.imports = [
    ./nixos.nix
    ./vm.nix
  ];

  flake.modules.darwin.system.imports = [
    ./darwin.nix
    ./pmset.nix
  ];
}
