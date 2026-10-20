{ inputs, ... }:
{
  imports = [
    inputs.self.modules.nixos.claude-code
    inputs.self.modules.nixos.codex
    inputs.self.modules.nixos.packages
    ./default-apps.nix
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
