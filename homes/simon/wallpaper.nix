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

  # DMS owns session.json and watches it, so merging in place is enough.
  # wallpaperPath is only seeded, since cycling rewrites it as it goes.
  apply = pkgs.writeShellScript "dms-wallpaper" ''
    set -eu
    mkdir -p "$(dirname ${sessionFile})"
    [ -f ${sessionFile} ] || echo '{}' > ${sessionFile}

    tmp=$(mktemp ${sessionFile}.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    ${lib.getExe pkgs.jq} \
      --argjson managed ${lib.escapeShellArg (builtins.toJSON managed)} \
      '. as $orig
       | . * $managed
       | if ($orig.wallpaperPath // "") != "" then .wallpaperPath = $orig.wallpaperPath else . end' \
      ${sessionFile} > "$tmp"
    mv "$tmp" ${sessionFile}
    trap - EXIT
  '';
in
{
  home.file.".local/share/wallpapers".source = wallpapers;

  home.activation.dmsWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${apply}
  '';
}
