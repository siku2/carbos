{
  config,
  ...
}:
{
  imports = [
    ./disk.nix
    ./hardware.nix
    ../../../modules
  ];

  networking.hostName = "carbon-x1";

  home-manager.users.${config.carbos.user.login}.carbos.wallpaper = {
    width = 2560;
    height = 1440;
  };

  system.stateVersion = "26.05";

  virtualisation.vmVariant = {
    users.users.${config.carbos.user.login}.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJc/x0F5XV2bnqHZFHZUlPmY/D24+mxhAWOR8D5LjyVi carbon-x1"
    ];
  };
}
