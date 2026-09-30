{ pkgs, ... }:
let
  claude-plugins-official = pkgs.fetchFromGitHub {
    owner = "anthropics";
    repo = "claude-plugins-official";
    rev = "517b2fcd1b60fa2181ac52dcf8492361ba341180";
    hash = "sha256-BkkIWwbGj8RtGFCXY3+McPzLmP9pYhWMAmpZsVUMi4M=";
  };

  claude-code = pkgs.symlinkJoin {
    name = "claude-code";
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude --add-flags --allow-dangerously-skip-permissions
    '';
    inherit (pkgs.claude-code) meta;
  };
in
{
  imports = [ ./home/rdp.nix ];

  home = {
    username = "simon";
    stateVersion = "26.05";
  };

  rdp.connections.enif = {
    "full address" = "enif.pegasus.inomo.tech";
    username = "Administrator";
  };

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
          list-dead-branches = "!git branch -vv | awk '/: gone]/{print $1}'";
          prune-dead-branches = "!f() { git fetch --prune && git list-dead-branches | while read branch; do git branch -D \"$branch\"; done; }; f";
        };
      };
    };

    gpg.enable = true;

    ssh = {
      enable = true;
      enableDefaultConfig = false;
      settings = {
        "*" = {
          # Need to override this because the macOS default is just "UTF-8".
          SendEnv = "LC_CTYPE";
          SetEnv.LC_CTYPE = "en_US.UTF-8";
        };

        olu-dev-proxy = {
          HostName = "autopi-1faf5d7aad13afa15bae7497fdce0f00";
          User = "pi";
        };

        olu-dev = {
          HostName = "192.168.1.101";
          ProxyJump = "olu-dev-proxy";
          User = "root";
          IdentityFile = "~/Documents/certificates/olu-dev/id_ssh_dev10";
          PubkeyAcceptedKeyTypes = "+ssh-rsa";
          HostKeyAlgorithms = "+ssh-rsa";
        };

        tailscale-relay = {
          HostName = "tailscale-relay.bt12.inomo.tech";
          User = "simon";
        };

        forgejo-runner = {
          HostName = "forgejo-runner.bt12.inomo.tech";
          User = "simon";
        };

        github-runner = {
          HostName = "github-runner.bt12.inomo.tech";
          User = "simon";
        };

        sw1 = {
          HostName = "sw1.bt12.inomo.tech";
          User = "manager";
          KexAlgorithms = "+diffie-hellman-group14-sha1";
          HostKeyAlgorithms = "+ssh-rsa";
        };
      };
    };

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

      stdlib = ''
        use_preset() {
          if [ ''$# -eq 0 ]; then
            log_error "use preset: expected at least one preset name"
            return 1
          fi

          local names
          names="''$(printf '%s\n' "''$@" | sort -u | tr '\n' '+' | sed 's/+''$//')"

          use flake "path:/private/etc/nix-darwin#''${names}"
        }
      '';
    };

    starship = {
      enable = true;
      settings.gcloud.disabled = true;
    };

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
        zed = "zeditor";
      };
    };

    zed-editor = {
      enable = true;
      defaultEditor = true;
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
      package = claude-code;
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
