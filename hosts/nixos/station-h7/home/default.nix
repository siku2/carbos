{
  imports = [
    ./mic.nix
    ./niri.nix
    ./steam.nix
  ];

  # Vesktop instead of the official client: it can share audio on Wayland.
  carbos.vesktop = {
    enable = true;
    plugins.VoiceCallBridge.enable = true;
    # The mic chain already cleans up the voice.
    inputProfile = "STUDIO";
  };

  # Calls from the VoiceCallBridge plugin of the Vesktop above.
  carbos.dms = {
    plugins.voiceCall.enable = true;
    bars.default.center = [ "voiceCall" ];
  };

  # Antialiasing renders at twice the canvas size. A full-width canvas at 2x
  # HiDPI then exceeds the GPU's 16384 px limit and KiCad drops to software.
  carbos.kicad.graphics.antialiasing = "none";

  carbos.ardour = {
    enable = true;
    appearance.fontScale = 150;
  };

  carbos.wallpaper = {
    width = 7680;
    height = 2160;
  };
}
