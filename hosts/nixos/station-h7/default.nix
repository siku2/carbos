{
  config,
  inputs,
  ...
}:
{
  imports = [
    inputs.chaotic.nixosModules.default
    ./audio.nix
    ./disk.nix
    ./gaming.nix
    ./hardware.nix
    ../../../modules
  ];

  networking.hostName = "station-h7";

  home-manager.users.${config.carbos.user.login}.imports = [ ./home ];

  system.stateVersion = "26.05";
}
