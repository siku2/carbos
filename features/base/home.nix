{ osConfig, pkgs, ... }:
{
  home = {
    stateVersion = "26.05";
    username = osConfig.carbos.user.login;
    homeDirectory = "/home/${osConfig.carbos.user.login}";

    packages = with pkgs; [
      ansifilter
      devcontainer
      forgejo-cli
    ];
  };

  # Generating it pulls in an options.json derivation that nix warns about.
  manual.manpages.enable = false;

  programs = {
    home-manager.enable = true;

    fish = {
      enable = true;
      interactiveShellInit = ''
        set -g fish_greeting
      '';
    };

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
        mindaro = {
          hostname = "mindaro.local.bg12.ch";
          user = "simon";
        };
        station-h7 = {
          hostname = "station-h7.local.bg12.ch";
          user = "simon";
        };
      };
    };
  };
}
