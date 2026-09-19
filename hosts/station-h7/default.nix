{ lib, ... }:
{
  imports = [
    ./disk.nix
    ./hardware.nix
    ../../modules
  ];

  networking.hostName = "station-h7";

  system.stateVersion = "26.05";

  virtualisation.vmVariant = {
    virtualisation = {
      cores = 4;
      memorySize = 4096;
      resolution = {
        x = 1920;
        y = 1080;
      };
      qemu.options = [ "-device virtio-vga-gl" ];
    };

    services.openssh.enable = true;

    networking.firewall.enable = lib.mkForce false;
  };
}
