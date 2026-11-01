{ config, lib, ... }:
let
  inherit (config.carbos.registry) hosts sshKeys;
in
{
  services.openssh = {
    enable = true;
    startWhenNeeded = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.${config.carbos.user.login}.openssh.authorizedKeys.keys = [ sshKeys.carbon-x1 ];

  programs.ssh.knownHosts = lib.mapAttrs (_: host: {
    hostNames = [ host.fqdn ];
    publicKey = host.hostKey;
  }) (lib.filterAttrs (_: host: host.hostKey != null) hosts);
}
