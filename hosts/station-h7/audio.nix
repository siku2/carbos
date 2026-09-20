{
  # DisplayLink's SPDIF outranks the SSL 2 MkII by default (1108 vs 1100 for
  # sinks, 2108 vs 2100 for sources), so wireplumber would pick it.
  services.pipewire.wireplumber.extraConfig."51-ssl2-defaults" = {
    "monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "alsa_output.usb-Solid_State_Logic_SSL_2_Mk_II-00.HiFi__Line__sink"; }
        ];
        actions.update-props = {
          "priority.driver" = 3000;
          "priority.session" = 3000;
        };
      }
      {
        matches = [
          { "node.name" = "alsa_input.usb-Solid_State_Logic_SSL_2_Mk_II-00.HiFi__Mic1__source"; }
        ];
        actions.update-props = {
          "priority.driver" = 3000;
          "priority.session" = 3000;
        };
      }
    ];
  };
}
