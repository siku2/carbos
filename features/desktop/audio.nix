{ config, ... }:
{
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
  };

  security.rtkit.enable = true;

  # For the rtprio rlimit, so PipeWire clients go realtime without rtkit.
  users.users.${config.carbos.user.login}.extraGroups = [ "pipewire" ];
}
