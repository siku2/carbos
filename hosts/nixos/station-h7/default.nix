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

  # Shows calls from the VoiceCallBridge plugin of the Vesktop install in ./home.
  programs.dms-shell.plugins.VoiceCall.src = ../../../modules/dms-plugins/VoiceCall;

  system.stateVersion = "26.05";
}
