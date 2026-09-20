{ config, ... }:
let
  device = "/dev/disk/by-id/nvme-eui.0025384231407851";
in
{
  disko.devices = {
    disk.main = {
      inherit device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          esp = {
            name = "ESP";
            type = "EF00";
            size = "2G";
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
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                # Already compressed, so zstd only costs cpu. Split from
                # /home, but compatdata's wine prefixes are game state.
                "/games" = {
                  mountpoint = "/games";
                  mountOptions = [
                    "compress=no"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /games 0755 ${config.carbos.user.login} users -"
  ];
}
