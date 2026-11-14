{
  pkgs,
  ...
}:
{
  environment.systemPackages = [
    # Qt's default theme name. Without it, icon lookup fails outright.
    pkgs.adwaita-icon-theme
  ];

  services.printing = {
    enable = true;
    # CUPS makes temporary queues itself. cups-browsed would add permanent ones.
    browsed.enable = false;
  };
  # CUPS finds IPP Everywhere printers over mDNS and makes queues on demand.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };
  # Avahi owns mDNS. Two responders on port 5353 make discovery unreliable.
  services.resolved.settings.Resolve.MulticastDNS = false;

  services.upower.enable = true;

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
