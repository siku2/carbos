{ pkgs, ... }:
{
  imports = [
    ./git.nix
    ./ssh.nix
    ./zsh.nix
  ];

  carbos.user.projectsDirectory = "/Volumes/Projects";

  home = {
    packages = with pkgs; [
      nil
      nixd
      nixfmt
    ];
  };

  rdp.connections.enif = {
    "full address" = "enif.pegasus.inomo.tech";
    username = "Administrator";
  };

  programs = {
    bash.enable = true;
    gpg.enable = true;
  };

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry_mac;
    defaultCacheTtl = 600;
    maxCacheTtl = 7200;
  };
}
