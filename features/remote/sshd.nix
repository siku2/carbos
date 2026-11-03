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
      # Drops dead sessions, and with them their forwarded connections.
      ClientAliveInterval = 10;
    };
  };

  users.users.${config.carbos.user.login}.openssh.authorizedKeys.keys = [ sshKeys.carbon-x1.line ];

  programs.ssh.knownHosts = lib.mapAttrs (_: host: {
    hostNames = [ host.fqdn ];
    publicKey = host.hostKey.line;
  }) (lib.filterAttrs (_: host: host.hostKey != null) hosts);
}
