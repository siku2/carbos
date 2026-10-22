{ inputs, ... }:
{
  imports = [
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
  ]
  ++ (with inputs.self.modules.nixos; [
    claude-code
    cli
    codex
    direnv
    gh
    git
    packages
    rust
    starship
    zed
  ]);
}
