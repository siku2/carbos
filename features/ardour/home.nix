{ config, pkgs, ... }:
{
  imports = [ ./module.nix ];

  carbos.ardour = {
    plugins = with pkgs; [
      lsp-plugins
      x42-plugins
    ];

    engine.jack = true;

    general = {
      sessionDir = "${config.xdg.userDirs.documents}/Ardour";
      clipLibraryDir = "${config.xdg.dataHome}/sounds/clips";
    };
  };
}
