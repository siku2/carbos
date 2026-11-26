{ config, inputs, ... }:
{
  imports = [
    ./android.nix
    ./disk.nix
    ./hardware.nix
  ]
  ++ (with inputs.self.modules.nixos; [
    nix
    remote
    shell
    system
  ]);

  networking.hostName = "fizzy";

  home-manager.users.${config.carbos.user.login}.home.stateVersion = "26.05";

  system.stateVersion = "26.05";
}
