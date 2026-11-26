{ pkgs, ... }:
{
  carbos.waydroid = {
    overlays = [ "com.android.internal.systemui.navbar.gestural" ];
    apps = [ pkgs.home-assistant-android ];
  };
}
