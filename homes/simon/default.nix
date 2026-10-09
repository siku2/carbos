{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  # home-manager builds the extraPackages wrapper inline and never exposes it,
  # so both of these resolve "zeditor" from PATH rather than from pkgs.
  zedPager = pkgs.writeShellScriptBin "zed-pager" ''
    ${lib.getExe pkgs.ansifilter} --text | zeditor -e -
  '';

  zedCli = pkgs.writeShellScriptBin "zed" ''
    exec zeditor "$@"
  '';
in
{
  imports = [
    ./ai.nix
    ./atuin.nix
    ./bitwarden.nix
    ./dms.nix
    ./dsearch.nix
    ./firefox.nix
    ./fractal.nix
    ./git.nix
    ./gtk.nix
    ./keyring.nix
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
  ]);

  carbos.user = {
    inherit (osConfig.carbos.user) fullName email;
  };

  home = {
    stateVersion = "26.05";
    username = osConfig.carbos.user.login;
    homeDirectory = "/home/${osConfig.carbos.user.login}";

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
      kicad
      libsecret
      nautilus
      nextcloud-talk-desktop
      plexamp
      seahorse
      secretspec
      wl-clipboard
      zedCli
      zedPager
    ];
  };

  xdg.configFile."secretspec/config.toml".source =
    (pkgs.formats.toml { }).generate "secretspec-config.toml"
      {
        defaults.provider = "keyring";
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

    foot = {
      enable = true;
      settings = {
        main = {
          font = "${osConfig.carbos.fonts.mono.name}:size=${toString osConfig.carbos.fonts.mono.size}";
        };
      };
    };

    zed-editor = {
      enable = true;
      package = pkgs.zed-editor;
      extraPackages = [
        pkgs.bash-language-server
        pkgs.nil
        pkgs.nixd
        pkgs.package-version-server
        pkgs.vscode-langservers-extracted
      ];
      extensions = [
        "cargo-tom"
        "dockerfile"
        "git-firefly"
        "html"
        "nix"
        "sql"
        "toml"
        "xml"
      ];
      userSettings = {
        auto_update = false;
        buffer_font_family = osConfig.carbos.fonts.mono.name;
        cli_default_open_behavior = "new_window";
        edit_predictions.provider = "copilot";
        git_panel.tree_view = true;
        session.trust_all_worktrees = true;
        disable_ai = true;
        terminal.env = {
          EDITOR = "zed -ew";
          VISUAL = "zed -ew";
          PAGER = "zed-pager";
        };
      };
      userKeymaps = [
        {
          context = "Terminal";
          bindings = {
            ctrl-p = null;
          };
        }
      ];
    };
  };
}
