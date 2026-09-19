_: {
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

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
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

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  security.rtkit.enable = true;

  services.upower.enable = true;

  services.fstrim.enable = true;

  hardware.bluetooth.enable = true;

  zramSwap.enable = true;
}
