{ pkgs, ... }:
{
  services.printing = {
    enable = true;
    # Only cupsd generates queues, so clients can keep the stock libcups.
    package = pkgs.cups.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        # Driverless queues for color printers that report
        # print-color-mode-default=auto otherwise default to grayscale.
        ./auto-color-default.patch
      ];
    });
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
}
