{ inputs, ... }:
{
  imports = [
    inputs.self.modules.nixos.unstable
    ./desktop.nix
    ./fonts.nix
    ./options.nix
    ./packages.nix
    ./rlbot.nix
    ./system.nix
    ./thinkpad.nix
    ./unfree.nix
    ./user.nix
    ./vm.nix
  ];
}
