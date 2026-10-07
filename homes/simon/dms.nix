{ lib, pkgs, ... }:
let
  pluginSettings = (pkgs.formats.json { }).generate "dms-plugin-settings.json" {
    webSearch.enabled = true;
  };
in
{
  # DMS rewrites this file at runtime, so it is seeded once and then left alone.
  home.activation.dmsPluginSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    target="$HOME/.config/DankMaterialShell/plugin_settings.json"
    [ -e "$target" ] || run ${pkgs.coreutils}/bin/install -Dm644 ${pluginSettings} "$target"
  '';
}
