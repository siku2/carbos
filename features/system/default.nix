{
  flake.modules.nixos.system.imports = [
    ./fonts.nix
    ./nixos.nix
    ./vm.nix
  ];

  flake.modules.darwin.system.imports = [
    ./darwin.nix
    ./fonts.nix
    ./pmset.nix
  ];
}
