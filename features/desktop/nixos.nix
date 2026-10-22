{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    # Qt's default theme name. Without it, icon lookup fails outright.
    pkgs.adwaita-icon-theme
  ];

  services.printing.enable = true;

  # Nautilus needs gvfs for trash and network mounts, udisks2 to mount media.
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  carbos.defaultApps = {
    decibels.mimeTypes = [ "audio/*" ];
    loupe.mimeTypes = [ "image/*" ];
    papers.mimeTypes = [ "application/pdf" ];
    showtime.mimeTypes = [ "video/*" ];
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
