{
  config,
  lib,
  pkgs,
  ...
}:
let
  toml = pkgs.formats.toml { };

  settings = {
    index_all_files = true;

    index_paths = [
      {
        path = config.home.homeDirectory;
        max_depth = 6;
        exclude_hidden = true;
        extract_exif = true;
        merge_default_exclude_dirs = true;
        exclude_dirs = [ ];
      }
      {
        path = "${config.home.homeDirectory}/Projects";
        max_depth = 0;
        exclude_hidden = true;
        extract_exif = false;
        merge_default_exclude_dirs = true;
        # "result" is a store symlink, following it would pull in the closure.
        exclude_dirs = [
          ".direnv"
          "result"
        ];
      }
    ];
  };
in
{
  home.packages = [ pkgs.dsearch ];

  xdg.configFile."danksearch/config.toml".source = toml.generate "dsearch.toml" settings;

  systemd.user.services.dsearch = {
    Unit = {
      Description = "dsearch file index";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.dsearch} serve";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
