{
  config,
  pkgs,
  ...
}:
{
  programs.niri.enable = true;

  programs.dms-shell.enable = true;

  services.displayManager.dms-greeter = {
    enable = true;
    compositor.name = "niri";
    configHome = "/home/${config.carbos.user.login}";
  };

  environment.systemPackages = [ pkgs.xwayland-satellite ];

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
