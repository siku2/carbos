{
  config,
  inputs,
  ...
}:
{
  imports = [
    ./disk.nix
    ./hardware.nix
  ]
  ++ (with inputs.self.modules.nixos; [
    base
    desktop
    remote
    thinkpad
  ]);

  networking.hostName = "carbon-x1";

  home-manager.users.${config.carbos.user.login}.carbos.wallpaper = {
    width = 2560;
    height = 1440;
  };

  system.stateVersion = "26.05";
}
