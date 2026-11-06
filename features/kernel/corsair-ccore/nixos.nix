{ config, lib, ... }:
{
  options.carbos.kernel.drivers.corsairCcore.enable =
    lib.mkEnableOption "the Corsair iCUE Commander Core driver";

  config.boot.extraModulePackages = lib.mkIf config.carbos.kernel.drivers.corsairCcore.enable [
    (config.boot.kernelPackages.callPackage ./package.nix { })
  ];
}
