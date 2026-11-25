{ config, inputs, ... }:
{
  imports = [
    ./hardware.nix
    ./macros.nix
    ./printer.nix
    ./wifi.nix
  ]
  ++ (with inputs.self.modules.nixos; [
    firmware
    nix
    remote
  ]);

  networking.hostName = "filamancer";

  time.timeZone = "Europe/Zurich";

  home-manager.users.${config.carbos.user.login}.home.stateVersion = "26.05";

  system.stateVersion = "26.05";
}
