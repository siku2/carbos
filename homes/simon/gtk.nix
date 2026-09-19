_: {
  # DMS's matugen writes dank-colors.css on every theme change, but nothing
  # pulls it in on its own.
  xdg.configFile = {
    "gtk-3.0/gtk.css".text = ''@import "dank-colors.css";'';
    "gtk-4.0/gtk.css".text = ''@import "dank-colors.css";'';
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
}
