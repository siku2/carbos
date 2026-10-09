{ config, ... }:
{
  system.nixos = {
    distroId = "carbos";
    distroName = "CarbOS";
  };

  boot.plymouth.enable = true;

  boot.kernelParams = [ "quiet" ];

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  programs.nh = {
    enable = true;
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep-since 30d";
    };
  };

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

  systemd.tmpfiles.rules = [
    "d /etc/nixos 0755 ${config.carbos.user.login} users -"
  ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  security.rtkit.enable = true;

  services.upower.enable = true;

  services.fwupd.enable = true;

  services.fstrim.enable = true;

  services.smartd = {
    enable = true;
    notifications.wall.enable = false;
    notifications.systembus-notify.enable = true;
  };

  zramSwap.enable = true;
}
