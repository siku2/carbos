{ config, lib, ... }:
{
  options.carbos.kernel.fixes.amdgpuMstWake.enable =
    lib.mkEnableOption "the amdgpu fixes for MST monitors that fail to wake";

  # DDC/CI from userspace races AUX and aborts link training. amdgpu 7.3 then
  # allocates an MST payload on the dead link, and the leaked start slot keeps
  # the stream outside the payload table until reboot. drm/amd#6047,
  # drm/amd#6049.
  config.boot.kernelPatches = lib.mkIf config.carbos.kernel.fixes.amdgpuMstWake.enable [
    {
      name = "drm-dp-mst-start-slot";
      patch = ./drm-dp-mst-start-slot.patch;
    }
    {
      name = "drm-amd-dpms-abort-failed-mst";
      patch = ./drm-amd-dpms-abort-failed-mst.patch;
    }
    {
      name = "drm-amd-dm-i2c-aux-lock";
      patch = ./drm-amd-dm-i2c-aux-lock.patch;
    }
  ];
}
