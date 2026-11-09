{ config, pkgs, ... }:
{
  programs.dms-shell.enable = true;
  # dms exits with 128 + SIGTERM when it is stopped.
  systemd.user.services.dms.serviceConfig.SuccessExitStatus = 143;
  # A crash drops the D-Bus name and systemd stops the unit cleanly.
  systemd.user.services.dms.serviceConfig.Restart = "always";

  services.displayManager.dms-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/${config.carbos.user.login}";
  };

  services.displayManager.autoLogin = {
    enable = true;
    user = config.carbos.user.login;
  };

  # DMS uses this for its printer management UI.
  environment.systemPackages = [ pkgs.cups-pk-helper ];
}
