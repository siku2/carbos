{
  lib,
  pkgs,
  ...
}:
{
  home.packages = [ pkgs.fractal ];

  # Fractal has no tray and no background mode. close_request proceeds, so
  # closing the window exits the process and notifications stop with it.
  # Keeping it running from login is the only way to get notified.
  systemd.user.services.fractal = {
    Unit = {
      Description = "Fractal";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = lib.getExe pkgs.fractal;
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
