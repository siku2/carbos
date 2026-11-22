{
  config,
  inputs,
  ...
}:
let
  inherit (config.carbos.registry) sshKeys;
in
{
  imports = [
    ./hardware.nix
    ./wifi.nix
  ]
  ++ (with inputs.self.modules.nixos; [
    nix
    remote
  ]);

  networking.hostName = "filamancer";

  time.timeZone = "Europe/Zurich";

  users.users.${config.carbos.user.login}.openssh.authorizedKeys.keys = [ sshKeys.itma-23001.line ];

  home-manager.users.${config.carbos.user.login}.home.stateVersion = "26.05";

  system.stateVersion = "26.05";
}
