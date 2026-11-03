{ config, ... }:
{
  nix.settings.auto-optimise-store = true;

  programs.nh = {
    enable = true;
    flake = "/etc/nixos";
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep-since 30d";
    };
  };

  systemd.tmpfiles.rules = [
    "d /etc/nixos 0755 ${config.carbos.user.login} users -"
  ];
}
