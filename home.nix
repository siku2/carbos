{ pkgs, ... }:
let
  claude-plugins-official = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-plugins-official";
    rev = "517b2fcd1b60fa2181ac52dcf8492361ba341180";
    hash = "sha256-BkkIWwbGj8RtGFCXY3+McPzLmP9pYhWMAmpZsVUMi4M=";
  };
in
{
  home.username = "simon";
  home.stateVersion = "26.05";

  programs = {
    git = {
      enable = true;
      lfs.enable = true;
    };

    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    starship.enable = true;

    bash.enable = true;
    zsh = {
      enable = true;

      oh-my-zsh = {
        enable = true;

        plugins = [
          "git"
          "macos"
          "rust"
        ];
      };

      shellAliases = {
        x = "cargo run --quiet --bin xtask --";
      };
    };

    codex = {
      enable = true;
    };

    claude-code = {
      enable = true;
      plugins = [
        "${claude-plugins-official}/plugins/frontend-design"
        "${claude-plugins-official}/plugins/rust-analyzer-lsp"
        (pkgs.fetchFromGitHub {
          owner = "openai";
          repo = "codex-plugin-cc";
          rev = "db52e28f4d9ded852ab3942cea316258ae4ef346";
          hash = "sha256-BkkIWwbGj8RtGFCXY3+McPzLmP9pYhWMAmpZsVUMi4M=";
        })
      ];
      settings = {
        env = {
          CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY = "1";
        };
        includeCoAuthoredBy = false;
        enableArtifact = false;
        feedbackDrafts = "off";
        askUserQuestionTimeout = "10m";
        skipDangerousModePermissionPrompt = true;
        skipWorkflowUsageWarning = true;
        switchModelsOnFlag = false;
      };
    };
  };

  home.packages = with pkgs; [
    age
    fd
    fzf
    jq
    nixd
    nil
    nixfmt
    ripgrep
    sops
    tree
    unzip
    wget
    yq
  ];
}
