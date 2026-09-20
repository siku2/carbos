{
  # Everything goes through the SSL 2 MkII, but it does not win on priority.
  # The DisplayLink dock's SPDIF outranks it both ways (1108 against 1100 for
  # sinks, 2108 against 2100 for sources) and the two mic inputs tie with each
  # other at 2100. Without this the easyeffects chain would process whatever
  # wireplumber happened to pick.
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
