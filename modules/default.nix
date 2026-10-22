{ config, inputs, ... }:
{
  imports = [
    ./default-apps.nix
    ./desktop.nix
    ./fonts.nix
    ./options.nix
    ./rlbot.nix
    ./thinkpad.nix
    inputs.self.modules.nixos.base
  ];

  home-manager.users.${config.carbos.user.login} = import ../homes/simon;
}
