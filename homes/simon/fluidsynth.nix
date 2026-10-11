{
  # Plays MIDI from apps like Audacity, which only send notes to a device.
  services.fluidsynth = {
    enable = true;
    soundService = "pipewire-pulse";
    # The default name contains the PID, so apps forget the device on restart.
    extraOptions = [ "-o midi.alsa_seq.id=GM" ];
  };

  # Its shell server listens on all interfaces and nothing turns it off.
  systemd.user.services.fluidsynth.Service.PrivateNetwork = true;
}
