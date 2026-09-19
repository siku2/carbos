{
  config,
  lib,
  pkgs,
  ...
}:
let
  # gnome-backgrounds ships JPEG XL and Qt has no plugin for it, so the dark
  # variants get decoded and scaled down to something a laptop can page in.
  wallpapers =
    pkgs.runCommand "gnome-wallpapers-dark"
      {
        nativeBuildInputs = [
          pkgs.libjxl
          pkgs.imagemagick
        ];
      }
      ''
        mkdir -p $out
        for f in ${pkgs.gnome-backgrounds}/share/backgrounds/gnome/*-d.jxl; do
          name=$(basename "$f" -d.jxl)
          djxl "$f" "$TMPDIR/$name.png"
          magick "$TMPDIR/$name.png" -resize 2560x2560 -quality 90 "$out/$name.jpg"
          rm "$TMPDIR/$name.png"
        done
      '';

  sessionFile = "${config.home.homeDirectory}/.local/state/DankMaterialShell/session.json";

  managed = {
    wallpaperPath = "${config.home.homeDirectory}/.local/share/wallpapers/adwaita.jpg";
    wallpaperCyclingEnabled = true;
    wallpaperCyclingMode = "interval";
    wallpaperCyclingInterval = 1800;
  };

  apply = pkgs.writeShellApplication {
    name = "dms-wallpaper";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./dms-wallpaper.sh;
  };
in
{
  home.file.".local/share/wallpapers".source = wallpapers;

  home.activation.dmsWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SESSION_FILE=${lib.escapeShellArg sessionFile} \
    MANAGED=${lib.escapeShellArg (builtins.toJSON managed)} \
    run ${lib.getExe apply}
  '';
}
