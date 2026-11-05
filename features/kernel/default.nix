{
  flake.modules.nixos.kernel.imports = [
    ./cachyos.nix
    ./ene-dram/nixos.nix
    ./sp5100-tco/nixos.nix
    ./amdgpu-mst-wake/nixos.nix
  ];
}
