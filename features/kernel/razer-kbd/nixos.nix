{ config, lib, ... }:
{
  options.carbos.kernel.drivers.razerKbd.enable =
    lib.mkEnableOption "the backlight driver for the Razer BlackWidow Chroma V2";

  config.boot.extraModulePackages = lib.mkIf config.carbos.kernel.drivers.razerKbd.enable [
    (config.boot.kernelPackages.callPackage ./package.nix { })
  ];
}
