{ config, lib, ... }:
let
  inherit (config.boot.kernelPackages) callPackage;
in
{
  options.carbos.kernel.fixes.amdgpuMstWake.enable =
    lib.mkEnableOption "the amdgpu fixes for MST monitors that fail to wake";

  # DDC/CI from userspace races AUX and aborts link training. amdgpu 7.3 then
  # allocates an MST payload on the dead link, and the leaked start slot keeps
  # the stream outside the payload table until reboot. drm/amd#6047,
  # drm/amd#6049.
  config.boot.extraModulePackages = lib.mkIf config.carbos.kernel.fixes.amdgpuMstWake.enable [
    (callPackage ../patched-module.nix {
      dir = "drivers/gpu/drm/display";
      modules = [ "drm_display_helper" ];
      patches = [ ./drm-dp-mst-start-slot.patch ];
    })
    (callPackage ../patched-module.nix {
      dir = "drivers/gpu/drm/amd/amdgpu";
      unpack = [ "drivers/gpu/drm/amd" ];
      modules = [ "amdgpu" ];
      patches = [
        ./drm-amd-dpms-abort-failed-mst.patch
        ./drm-amd-dm-i2c-aux-lock.patch
      ];
    })
  ];
}
