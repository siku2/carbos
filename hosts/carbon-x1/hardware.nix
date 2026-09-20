_: {
  nixpkgs.hostPlatform = "x86_64-linux";

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 20;
      };
      efi.canTouchEfiVariables = true;
    };
  };

  hardware = {
    cpu.intel.updateMicrocode = true;
    enableRedistributableFirmware = true;
    graphics.enable = true;
  };

  # Synaptics 06cb:00bd. Also turns on PAM fprintAuth.
  services.fprintd.enable = true;

  services.thermald.enable = true;

  # DYTC otherwise caps package power on AC.
  carbos.thinkpad.biosSettings = {
    AdaptiveThermalManagementAC = "MaximizePerformance";
  };
}
