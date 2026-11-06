{ config, lib, ... }:
{
  options.carbos.kernel.drivers.eneRgb.enable =
    lib.mkEnableOption "the driver for ENE (ASUS Aura) RGB controllers on DIMMs and GPUs";

  config.boot = lib.mkIf config.carbos.kernel.drivers.eneRgb.enable {
    extraModulePackages = [ (config.boot.kernelPackages.callPackage ./package.nix { }) ];
    kernelModules = [ "ene_rgb" ];
  };
}
