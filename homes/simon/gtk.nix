{ lib, pkgs, ... }:
{
  # DMS's matugen writes dank-colors.css on every theme change, but nothing
  # pulls it in on its own.
  gtk = {
    enable = true;
    colorScheme = "dark";
    gtk2.enable = false;
    gtk3.extraCss = ''@import "dank-colors.css";'';
    gtk4.extraCss = ''@import "dank-colors.css";'';
    # home-manager writes the enum's number, but GTK only parses its nick.
    gtk4.extraConfig.gtk-interface-color-scheme = "dark";
  };

  # Outside Plasma, KDE apps fall back to light Breeze. DMS's matugen writes
  # this scheme. kdeglobals stays writable because KDE apps store state in it.
  home.activation.kdeColorScheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kdeglobals \
      --group UiSettings --key ColorScheme DankMatugen
  '';
}
