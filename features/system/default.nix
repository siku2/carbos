{
  flake.modules.nixos.system.imports = [
    ./fonts.nix
    ./nixos.nix
    ./revision.nix
    ./vm.nix
  ];

  flake.modules.darwin.system.imports = [
    ./darwin.nix
    ./fonts.nix
    ./pmset.nix
    ./revision.nix
  ];
}
