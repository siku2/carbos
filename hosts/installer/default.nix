{
  lib,
  pkgs,
  ...
}:
{
  boot.initrd.systemd.enable = lib.mkForce false;

  hardware.enableRedistributableFirmware = lib.mkForce true;

  networking.hostName = "carbos-installer";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    disko
    git
    nixos-install-tools
    vim
  ];

  system.stateVersion = "26.05";
}
