{ lib, osConfig, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*" = {
        AddKeysToAgent = "yes";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
      };
    }
    // lib.mapAttrs (_: host: {
      hostname = host.fqdn;
      user = osConfig.carbos.user.login;
    }) osConfig.carbos.registry.hosts;
  };
}
