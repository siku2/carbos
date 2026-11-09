{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.carbos.kernel.drivers.razerKbd.enable =
    lib.mkEnableOption "the backlight driver for the Razer BlackWidow Chroma V2";

  config = lib.mkIf config.carbos.kernel.drivers.razerKbd.enable {
    boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ./package.nix { }) ];

    # The virtual LampArray device belongs to the seat, like the keyboard.
    services.udev.packages = [
      (pkgs.writeTextDir "lib/udev/rules.d/70-razer-kbd.rules" ''
        SUBSYSTEM=="hidraw", KERNELS=="0006:1532:0221.*", TAG+="uaccess"
      '')
    ];
  };
}
