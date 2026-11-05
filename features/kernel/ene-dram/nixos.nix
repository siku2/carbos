{ config, lib, ... }:
{
  options.carbos.kernel.drivers.eneDram.enable =
    lib.mkEnableOption "the driver for ENE (ASUS Aura) RGB controllers on DIMMs";

  config.boot = lib.mkIf config.carbos.kernel.drivers.eneDram.enable {
    extraModulePackages = [ (config.boot.kernelPackages.callPackage ./package.nix { }) ];
    kernelModules = [ "ene_dram" ];
  };
}
