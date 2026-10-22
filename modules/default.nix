{ config, inputs, ... }:
{
  imports = [
    inputs.self.modules.nixos.base
    inputs.self.modules.nixos.desktop
  ];

  home-manager.users.${config.carbos.user.login} = import ../homes/simon;
}
