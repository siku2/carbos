{ lib, ... }:
let
  # Written to the FAT partition after flashing, so the password stays out of the repo and store.
  envFile = "/boot/firmware/wifi.env";
in
{
  fileSystems."/boot/firmware".options = lib.mkForce [
    "nofail"
    "umask=0077"
  ];

  networking.networkmanager = {
    enable = true;
    ensureProfiles = {
      environmentFiles = [ envFile ];
      profiles.iot = {
        connection = {
          id = "iot";
          type = "wifi";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "iot.bg12.ch";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
  };

  systemd.services.NetworkManager-ensure-profiles.unitConfig.RequiresMountsFor = [ envFile ];
}
