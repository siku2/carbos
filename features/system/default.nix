{
  flake.modules.nixos.system.imports = [
    ./nixos.nix
    ./vm.nix
  ];
}
