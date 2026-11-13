{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.carbos.kernel.drivers.xone.enable =
    lib.mkEnableOption "xone with a fix for wired pads that go silent after suspend, in place of hardware.xone";

  # Same as hardware.xone, which offers no way to patch the module.
  config = lib.mkIf config.carbos.kernel.drivers.xone.enable {
    boot = {
      blacklistedKernelModules = [
        "xpad"
        "mt76x2u"
      ];
      extraModulePackages = [
        (config.boot.kernelPackages.xone.overrideAttrs (old: {
          patches = old.patches or [ ] ++ [ ./reset-stale-session.patch ];
        }))
      ];
    };
    hardware.firmware = [ pkgs.xone-dongle-firmware ];
    hardware.xpad-noone.enable = lib.mkDefault true;
  };
}
