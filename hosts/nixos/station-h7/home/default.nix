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

  carbos.wallpaper = {
    width = 7680;
    height = 2160;
  };
}
