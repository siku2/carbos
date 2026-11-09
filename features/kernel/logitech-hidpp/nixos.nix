{ config, lib, ... }:
{
  options.carbos.kernel.drivers.logitechHidpp.enable =
    lib.mkEnableOption "hid-logitech-hidpp with LED support, in place of the in-tree module";

  config.boot.extraModulePackages = lib.mkIf config.carbos.kernel.drivers.logitechHidpp.enable [
    (config.boot.kernelPackages.callPackage ./package.nix { })
  ];
}
