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

  environment.systemPackages = [
    pkgs.xwayland-satellite
    # DMS uses this for its printer management UI.
    pkgs.cups-pk-helper
    # Qt's default theme name. Without it, icon lookup fails outright.
    pkgs.adwaita-icon-theme
  ];

  services.printing.enable = true;

  # Nautilus needs gvfs for trash and network mounts, udisks2 to mount media.
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
