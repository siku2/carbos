{ config, lib, ... }:
{
  options.carbos.kernel.drivers.nzxtSmart2.enable =
    lib.mkEnableOption "nzxt-smart2 with LED support, in place of the in-tree module";

  config.boot.extraModulePackages = lib.mkIf config.carbos.kernel.drivers.nzxtSmart2.enable [
    (config.boot.kernelPackages.callPackage ./package.nix { })
  ];
}
