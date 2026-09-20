{ lib, ... }:
{
  # Shared by `nixos-rebuild build-vm` on every host. Hosts add their own ssh
  # keys, since there is no login password to fall back on.
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
