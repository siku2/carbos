{
  lib,
  osConfig,
  ...
}:
{
  home = {
    stateVersion = "26.05";
    username = osConfig.carbos.user.login;
    homeDirectory = "/home/${osConfig.carbos.user.login}";
  };

  # Generating it pulls in an options.json derivation that nix warns about.
  manual.manpages.enable = false;

  programs = {
    home-manager.enable = true;

    ssh = {
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
  };
}
