{ pkgs, ... }:
let
  # alsa-ucm-conf only knows the SSL 2 MkII from 1.2.16 on. Without it the mic
  # shows up as a 4 channel surround source instead of a mono Mic1. The patch
  # adds the 6 out and 8 in layout of firmware 1.16 and keeps outputs 3 and 4
  # to the SSL 2+.
  alsa-ucm-conf = pkgs.unstable.alsa-ucm-conf.overrideAttrs (old: {
    patches = old.patches or [ ] ++ [ ./ssl2-ucm.patch ];
  });
  ucm2 = "${alsa-ucm-conf}/share/alsa/ucm2";
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
          "node.description" = "RØDE Procaster (raw)";
          "node.nick" = "Procaster (raw)";
          "priority.driver" = 3000;
          "priority.session" = 3000;
        };
      }
    ];
  };

  # Nothing plays audio through the GPUs' display outputs. PCI addresses move
  # when the iGPU is toggled in the BIOS, so match the IDs.
  services.pipewire.wireplumber.extraConfig."51-hdmi-disable" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          {
            "device.vendor.id" = "0x1002";
            "device.product.id" = "~0x(ab30|1640)";
          }
        ];
        actions.update-props."device.disabled" = true;
      }
    ];
  };
}
