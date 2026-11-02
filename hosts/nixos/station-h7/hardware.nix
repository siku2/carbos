{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 20;
      };
      efi.canTouchEfiVariables = true;
    };

    # The 7800X3D is Zen 4, so the znver4 LTO build is the closest match.
    # It also carries CONFIG_AMD_PRIVATE_COLOR, which chaotic.hdr asserts on.
    kernelPackages = pkgs.linuxPackages_cachyos-lto-znver4;

    initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "ahci"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];

    kernelModules = [ "kvm-amd" ];
  };

  hardware = {
    cpu.amd.updateMicrocode = true;
    enableRedistributableFirmware = true;

    graphics = {
      enable = true;
      enable32Bit = true;
    };

    # Navi 31 clock and fan control, which is what LACT drives.
    amdgpu.overdrive.enable = true;
  };

  # In BACO the 7900 XTX misses DP hotplug, so a monitor turned on after boot
  # stays dark. amdgpu enables runtime PM at probe, so this has to run on bind.
  services.udev.extraRules = ''
    ACTION=="bind", SUBSYSTEM=="pci", DRIVER=="amdgpu", ATTR{vendor}=="0x1002", ATTR{device}=="0x744c", ATTR{power/control}="on"
  '';

  # When S3 aborts, systemd falls back to s2idle, which this board never
  # leaves on its own.
  systemd.sleep.settings.Sleep.SuspendState = "mem";
}
