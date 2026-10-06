{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ./module.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  boot.initrd.systemd.enable = lib.mkForce false;

  boot.loader = {
    grub.enable = lib.mkForce false;
    systemd-boot.enable = lib.mkForce false;
  };

  boot.kernelParams = lib.mkForce [
    "console=ttyS0,115200"
    "console=tty0"
    "loglevel=3"
    "panic=30"
    "boot.panic_on_fail"
  ];

  # kexec hands the kernel no EFI framebuffer, so nothing shows until i915
  # binds. Load it in the initrd for a console as early as possible.
  boot.initrd.kernelModules = [ "i915" ];

  hardware.enableRedistributableFirmware = lib.mkForce true;

  networking.hostName = "carbos-installer";

  system.stateVersion = "26.05";
}
