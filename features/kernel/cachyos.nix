{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.carbos.kernel.cachyos;
in
{
  options.carbos.kernel.cachyos = {
    enable = lib.mkEnableOption "the CachyOS LTO kernel. Needs the chaotic module";

    march = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "znver4";
      description = "Microarchitecture the kernel is built for. null is generic x86-64.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages =
      pkgs."linuxPackages_cachyos-lto${lib.optionalString (cfg.march != null) "-${cfg.march}"}";
  };
}
