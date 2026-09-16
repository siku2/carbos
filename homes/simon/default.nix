{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  zedPager = pkgs.writeShellScriptBin "zed-pager" ''
    ${lib.getExe pkgs.ansifilter} --text | ${lib.getExe pkgs.unstable.zed-editor} -e -
  '';
in
{
  imports = [
    ./ai.nix
    ./git.nix
    ./niri.nix
  ];

  home = {
    stateVersion = "26.05";
    username = osConfig.carbos.user.login;
    homeDirectory = "/home/${osConfig.carbos.user.login}";

    packages = with pkgs; [
      ansifilter
      bitwarden-cli
      devcontainer
      element-desktop
      firefox
      gh
      git-credential-manager
      inkscape
      kicad
      nextcloud-talk-desktop
      unstable.secretspec
      wl-clipboard
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
