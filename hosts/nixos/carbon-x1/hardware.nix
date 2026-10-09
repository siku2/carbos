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
    bluetooth.enable = true;
    cpu.intel.updateMicrocode = true;
    enableRedistributableFirmware = true;
    graphics.enable = true;
  };

  # Synaptics 06cb:00bd. Also turns on PAM fprintAuth.
  services.fprintd.enable = true;

  carbos.thinkpad.biosSettings = {
    # Unused on this machine, and all of it is attack surface.
    AbsolutePersistenceModuleActivation = "Disable";
    AMTControl = "Disable";
    LenovoCloudServices = "Disable";
    NfcAccess = "Disable";
    WirelessWANAccess = "Disable";

    # Already correct. Pinned so a CMOS reset cannot revert them.
    AdaptiveThermalManagementAC = "MaximizePerformance";
    AlwaysOnUSB = "Enable";
    BIOSUpdateByEndUsers = "Enable";
    ChargeInBatteryMode = "Enable";
    CPUPowerManagement = "Automatic";
    DataExecutionPrevention = "Enable";
    FingerprintReaderAccess = "Enable";
    HyperThreadingTechnology = "Enable";
    # Windows10 is modern standby and wrecks suspend battery life.
    SleepState = "Linux";
    # Enabling this would stop the machine booting without lanzaboote.
    SecureBoot = "Disable";
    SecurityChip = "Enable";
    SpeedStep = "Enable";
    # Assist mode is for Windows. Linux drives the controller itself.
    ThunderboltBIOSAssistMode = "Disable";
    VirtualizationTechnology = "Enable";
    VTdFeature = "Enable";
    WindowsUEFIFirmwareUpdate = "Enable";
  };

  carbos.thinkpad.batteryChargeLimit = 80;
}
