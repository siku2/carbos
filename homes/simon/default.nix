{
  inputs,
  osConfig,
  pkgs,
  ...
}:
{
  imports = [
    ./ai.nix
    ./atuin.nix
    ./bitwarden.nix
    ./dms
    ./dsearch.nix
    ./firefox.nix
    ./fractal.nix
    ./git.nix
    ./gtk.nix
    ./keyring.nix
    ./kicad
    ./rbw.nix
    ./wallpaper.nix
    ./nextcloud.nix
    ./niri.nix
  ]
  ++ (with inputs.self.modules.homeManager; [
    claude-code
    cli
    codex
    direnv
    git
    rust
    starship
    zed
  ]);

  carbos.user = {
    inherit (osConfig.carbos.user) fullName email;
  };

  home = {
    stateVersion = "26.05";
    username = osConfig.carbos.user.login;
    homeDirectory = "/home/${osConfig.carbos.user.login}";

    # AccountsService falls back to this when no icon is set.
    file.".face".source = ./files/avatar.png;

    packages = with pkgs; [
      ansifilter
      bitwarden-cli
      bitwarden-desktop
      devcontainer
      file-roller
      forgejo-cli
      gh
      git-credential-manager
      inkscape
      libsecret
      nautilus
      nextcloud-talk-desktop
      plexamp
      seahorse
      secretspec
      wl-clipboard
    ];
  };

  xdg.configFile."secretspec/config.toml".source =
    (pkgs.formats.toml { }).generate "secretspec-config.toml"
      {
        defaults.provider = "keyring";
      };

  xdg.userDirs.enable = true;

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

    foot = {
      enable = true;
      settings = {
        main = {
          font = "${osConfig.carbos.fonts.mono.name}:size=${toString osConfig.carbos.fonts.mono.size}";
        };
      };
    };

    zed-editor.userSettings.buffer_font_family = osConfig.carbos.fonts.mono.name;
  };
}
