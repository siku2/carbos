{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  cfg = config.carbos.wallpaper;

  # Where to anchor the crop when the screen is wider than the images.
  sets = {
    beach = "North";
    cliffs = "Center";
    desert = "Center";
    lake = "South";
  };

  # The macOS Big Sur dynamic wallpapers, 6016x3384 with one image per time of
  # day. Each set has 0.jpg to 23.jpg, symlinked to the image for that hour.
  source = pkgs.fetchFromGitHub {
    owner = "adi1090x";
    repo = "dynamic-wallpaper";
    rev = "65d515de0dc0625a3c405cfb232aee4f0048c5c4";
    sparseCheckout = map (set: "images/${set}") (lib.attrNames sets);
    hash = "sha256-/40e2V2ev4uVWepkz+MTeN7/hDCkMG3uSF7OeLXXPdY=";
  };

  size = "${toString cfg.width}x${toString cfg.height}";

  # DMS keeps the path it was given, so it must survive rebuilds and gc.
  dir = ".local/share/wallpapers";

  wallpapers =
    pkgs.runCommand "big-sur-wallpapers-${size}" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        render() {
          local set=$1 gravity=$2
          mkdir -p $out/$set
          for f in ${source}/images/$set/*.jpg; do
            if [ -L "$f" ]; then
              cp -P "$f" $out/$set/
            else
              magick "$f" -resize ${size}^ -gravity "$gravity" -extent ${size} \
                -quality 90 $out/$set/$(basename "$f")
            fi
          done
        }

        ${lib.concatLines (lib.mapAttrsToList (set: gravity: "render ${set} ${gravity}") sets)}
      '';

  apply = pkgs.writeShellApplication {
    name = "dms-wallpaper";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./dms-wallpaper.sh;
  };

  pick = pkgs.writeShellApplication {
    name = "dms-wallpaper-pick";
    runtimeInputs = [
      pkgs.coreutils
      osConfig.programs.dms-shell.package
    ];
    runtimeEnv = {
      WALLPAPERS = "${config.home.homeDirectory}/${dir}";
      WALLPAPER_SETS = lib.concatStringsSep " " (lib.attrNames sets);
    };
    text = builtins.readFile ./dms-wallpaper-pick.sh;
  };
in
{
  options.carbos.wallpaper = {
    width = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Width in pixels the wallpapers are rendered at.";
    };

    height = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Height in pixels the wallpapers are rendered at.";
    };
  };

  config = {
    home.file.${dir}.source = wallpapers;

    home.activation.dmsWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SESSION_FILE=${lib.escapeShellArg "${config.home.homeDirectory}/.local/state/DankMaterialShell/session.json"} \
      MANAGED=${lib.escapeShellArg (builtins.toJSON { wallpaperCyclingEnabled = false; })} \
      run ${lib.getExe apply}
    '';

    systemd.user.services.dms-wallpaper = {
      Unit = {
        Description = "Set the wallpaper for the day and hour";
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "dms.service"
        ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe pick;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.timers.dms-wallpaper = {
      Unit.Description = "Set the wallpaper every hour";
      Timer.OnCalendar = "hourly";
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
