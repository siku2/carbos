{ inputs, ... }:
{
  imports = [
    inputs.self.modules.nixos.packages
    inputs.self.modules.nixos.unstable
    ./desktop.nix
    ./fonts.nix
    ./options.nix
    ./rlbot.nix
    ./system.nix
    ./thinkpad.nix
    ./unfree.nix
    ./user.nix
    ./vm.nix
  ];
}
