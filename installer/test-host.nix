# A host for the installer VM test, laid out like the real ones but small.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  disko.devices.disk.main = {
    device = "/dev/vdb";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        esp = {
          name = "ESP";
          type = "EF00";
          size = "512M";
          priority = 1;
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          name = "carbos";
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "/root".mountpoint = "/";
              "/nix".mountpoint = "/nix";
              "/home".mountpoint = "/home";
            };
          };
        };
      };
    };
  };

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = false;
  };

  documentation.enable = false;

  system.stateVersion = "26.05";
}
