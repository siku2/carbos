{
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
    ./bitwarden.nix
    ./dsearch.nix
    ./firefox.nix
    ./fractal.nix
    ./git.nix
    ./gtk.nix
    ./rbw.nix
    ./niri.nix
  ];

  home = {
    stateVersion = "26.05";
    username = osConfig.carbos.user.login;
    homeDirectory = "/home/${osConfig.carbos.user.login}";

    packages = with pkgs; [
      ansifilter
      bitwarden-cli
      bitwarden-desktop
      devcontainer
      gh
      git-credential-manager
      inkscape
      kicad
      libsecret
      nautilus
      nextcloud-talk-desktop
      seahorse
      unstable.secretspec
      wl-clipboard
      zedCli
      zedPager
    ];
  };

  programs = {
    home-manager.enable = true;

    fish = {
      enable = true;
      interactiveShellInit = ''
        set -g fish_greeting
      '';
    };

    starship.enable = true;

    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    atuin = {
      enable = true;
      package = pkgs.unstable.atuin;
      settings = {
        update_check = false;
        enter_accept = true;
        filter_mode_shell_up_key_binding = "session";
        inline_height = 30;
        inline_height_shell_up_key_binding = 10;
        show_tabs = false;
        sync = {
          records = true;
        };
      };
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
      package = pkgs.unstable.zed-editor;
      extraPackages = [
        pkgs.nil
        pkgs.nixd
      ];
      extensions = [
        "cargo-tom"
        "git-firefly"
        "html"
        "nix"
        "toml"
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
