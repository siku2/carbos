{ pkgs, ... }:
{
  system.nixos = {
    distroId = "carbos";
    distroName = "CarbOS";
  };

  boot.plymouth.enable = true;

  boot.kernelParams = [
    "quiet"
    # A hard lockup panics and reboots. systemd-pstore keeps the log.
    "nmi_watchdog=panic"
    "panic=10"
  ];

  boot.kernel.sysctl."kernel.sysrq" = 1;

  time.timeZone = "Europe/Zurich";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_NUMERIC = "en_GB.UTF-8";
      LC_TIME = "en_GB.UTF-8";
      LC_MONETARY = "en_GB.UTF-8";
      LC_PAPER = "en_GB.UTF-8";
      LC_MEASUREMENT = "en_GB.UTF-8";
    };
  };

  networking.networkmanager.enable = true;

  services.resolved.enable = true;

  environment.systemPackages = [
    pkgs.pciutils
    pkgs.usbutils
  ];

  services.fwupd.enable = true;

  services.fstrim.enable = true;

  services.smartd = {
    enable = true;
    notifications.wall.enable = false;
    notifications.systembus-notify.enable = true;
  };

  zramSwap.enable = true;
}
