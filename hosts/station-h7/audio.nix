{ pkgs, ... }:
let
  # alsa-ucm-conf only knows the SSL 2 MkII from 1.2.16 on. Without it the mic
  # shows up as a 4 channel surround source instead of a mono Mic1.
  ucm2 = "${pkgs.unstable.alsa-ucm-conf}/share/alsa/ucm2";
in
{
  systemd.user.services.pipewire.environment.ALSA_CONFIG_UCM2 = ucm2;
  systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = ucm2;

  # DisplayLink's SPDIF outranks the SSL 2 MkII by default (1108 vs 1100 for
  # sinks, 2108 vs 2100 for sources), so wireplumber would pick it.
  services.pipewire.wireplumber.extraConfig."51-ssl2-defaults" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "alsa_output.usb-Solid_State_Logic_SSL_2_Mk_II-00.HiFi__Line__sink"; }
        ];
        actions.update-props = {
          "node.description" = "Sennheiser HD 6XX";
          "node.nick" = "HD 6XX";
          "priority.driver" = 3000;
          "priority.session" = 3000;
        };
      }
      {
        matches = [
          { "node.name" = "alsa_input.usb-Solid_State_Logic_SSL_2_Mk_II-00.HiFi__Mic1__source"; }
        ];
        actions.update-props = {
          "node.description" = "RØDE Procaster";
          "node.nick" = "Procaster";
          "priority.driver" = 3000;
          "priority.session" = 3000;
        };
      }
    ];
  };
}
