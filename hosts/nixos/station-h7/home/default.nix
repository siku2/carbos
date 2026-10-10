{ pkgs, ... }:
{
  imports = [
    ./easyeffects.nix
    ./niri.nix
    ./steam.nix
  ];

  # Vesktop instead of the official client: it can share audio on Wayland.
  # Vencord comes from our overlay with the local plugins.
  home.packages = [ (pkgs.vesktop.override { withSystemVencord = true; }) ];

  # Calls from the VoiceCallBridge plugin of the Vesktop above.
  carbos.dms = {
    plugins.voiceCall.enable = true;
    bars.default.center = [ "voiceCall" ];
  };

  # Antialiasing renders at twice the canvas size. A full-width canvas at 2x
  # HiDPI then exceeds the GPU's 16384 px limit and KiCad drops to software.
  carbos.kicad.graphics.antialiasing = "none";

  carbos.wallpaper = {
    width = 7680;
    height = 2160;
  };
}
