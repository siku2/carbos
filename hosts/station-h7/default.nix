{
  config,
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.chaotic.nixosModules.default
    ./audio.nix
    ./disk.nix
    ./gaming.nix
    ./hardware.nix
    ./rgb.nix
    ../../modules
  ];

  networking.hostName = "station-h7";

  home-manager.users.${config.carbos.user.login}.imports = [ ./home ];

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
