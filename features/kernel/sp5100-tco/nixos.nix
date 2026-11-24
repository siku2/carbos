{ config, lib, ... }:
{
  options.carbos.kernel.fixes.sp5100Tco.enable =
    lib.mkEnableOption "the sp5100_tco fix for SMBus hangs at boot";

  # release_resource() skips the muxed region wakeup, so an SMBus transfer
  # that races the watchdog probe at boot sleeps forever.
  config.boot.extraModulePackages = lib.mkIf config.carbos.kernel.fixes.sp5100Tco.enable [
    (config.boot.kernelPackages.callPackage ../patched-module.nix {
      dir = "drivers/watchdog";
      modules = [ "sp5100_tco" ];
      patches = [ ./sp5100-tco-release-muxed.patch ];
    })
  ];
}
