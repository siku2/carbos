{
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ./module.nix
  ];

  # The netboot profile adds zfs, which nothing here uses.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  boot.loader = {
    grub.enable = lib.mkForce false;
    systemd-boot.enable = lib.mkForce false;
  };

  boot.consoleLogLevel = 3;
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty0"
    "panic=30"
    "boot.panic_on_fail"
  ];

  # kexec hands the kernel no EFI framebuffer, so nothing shows until i915
  # binds. Load it in the initrd for a console as early as possible.
  boot.initrd.kernelModules = lib.optionals pkgs.stdenv.hostPlatform.isx86 [ "i915" ];

  hardware.enableRedistributableFirmware = lib.mkForce true;

  networking.hostName = "carbos-installer";

  system.stateVersion = "26.05";
}
