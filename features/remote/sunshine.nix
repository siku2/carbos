{ pkgs, ... }:
{
  services.sunshine = {
    enable = true;
    autoStart = true;
    # For KMS capture, which niri needs.
    capSysAdmin = true;
    openFirewall = true;
  };

  environment.systemPackages = [ pkgs.moonlight-qt ];
}
