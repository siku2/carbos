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

  # Synaptics 06cb:00bd. Enabling this also turns on PAM fprintAuth, which is
  # what Bitwarden's biometric unlock goes through on Linux (via polkit).
  services.fprintd.enable = true;

  services.thermald.enable = true;
}
