{
  flake.modules.nixos.gaming.imports = [
    ./kytyps5.nix
    ./minecraft.nix
    ./rlbot.nix
    ./steam.nix
  ];
}
