{
  flake.modules.nixos.kernel.imports = [
    ./cachyos.nix
    ./ene-rgb/nixos.nix
    ./nzxt-smart2/nixos.nix
    ./corsair-ccore/nixos.nix
    ./razer-kbd/nixos.nix
    ./logitech-hidpp/nixos.nix
    ./sp5100-tco/nixos.nix
    ./amdgpu-mst-wake/nixos.nix
    ./xone/nixos.nix
  ];
}
