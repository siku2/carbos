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
    gh.enable = true;
    git = {
      enable = true;
      lfs.enable = true;
      ignores = [
        ".DS_Store"
        ".claude/"
        ".direnv/"
        "scratch/"
      ];
      settings = {
        user = {
          name = "Simon Berger";
          email = "simon.berger@inomotech.com";
          signingKey = "BAA343801A190591C8667BDFDA52A1F326E417A2";
        };
        commit.gpgSign = true;
        tag = {
          gpgSign = true;
          forceSignAnnotated = true;
        };
        push.gpgSign = "if-asked";
        credential.helper = "osxkeychain";
        init.defaultBranch = "main";
        rerere.enabled = true;
        alias = {
          list-stale-branches = "!git branch -vv | awk '/: gone]/{print $1}'";
          prune-stale-branches = "!f() { git fetch --prune && git list-stale-branches | while read branch; do git branch -d \"$branch\"; done; }; f";
        };
      };
    };

    gpg.enable = true;

    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
      config = {
        whitelist = {
          prefix = [ "/Volumes/Projects" ];
        };
      };
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
      # TODO: blocked by https://github.com/nix-community/home-manager/issues/9397
      # settings = {
      #   approvals_reviewer = "auto_review";

      #   model = "gpt-6-astra";
      #   model_reasoning_effort = "low";

      #   features = {
      #     prevent_idle_sleep = true;
      #   };
      # };
    };

    claude-code = {
      enable = true;
      plugins = [
        "${claude-plugins-official}/plugins/frontend-design"
        "${claude-plugins-official}/plugins/rust-analyzer-lsp"
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
    cargo-clean-all
    fd
    forgejo-cli
    fzf
    jq
    nil
    nixd
    nixfmt
    ripgrep
    sops
    tree
    unzip
    wget
    yq
  ];

  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry_mac;
    defaultCacheTtl = 600;
    maxCacheTtl = 7200;
  };
}
