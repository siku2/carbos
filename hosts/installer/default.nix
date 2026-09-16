{
  lib,
  pkgs,
  ...
}:
{
  boot.initrd.systemd.enable = lib.mkForce false;

  boot.kernelParams = lib.mkForce [
    "console=ttyS0,115200"
    "console=tty0"
    "panic=30"
    "boot.panic_on_fail"
  ];

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
