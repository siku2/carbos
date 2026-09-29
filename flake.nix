{
  description = "System flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      nix-darwin,
      home-manager,
      rust-overlay,
      treefmt-nix,
    }:
    let
      system = "aarch64-darwin";

      unstablePkgs = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          overlay
          rust-overlay.overlays.default
        ];
      };

      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      overlay = final: prev: {
        codex = unstablePkgs.codex;
        claude-code = unstablePkgs.claude-code;

        # These apps normally self-update. Under nix they are pinned to the flake,
        # so track unstable to pick up security releases sooner.
        firefox-bin = unstablePkgs.firefox-bin;
        google-chrome = unstablePkgs.google-chrome;
        _1password-cli = unstablePkgs._1password-cli;
        _1password-gui = unstablePkgs._1password-gui;

        claude-desktop = final.callPackage ./pkgs/claude-desktop.nix { };

        cargo-clean-all = prev.rustPlatform.buildRustPackage {
          pname = "cargo-clean-all";
          version = "0.6.5";

          src = prev.fetchFromGitHub {
            owner = "dnlmlr";
            repo = "cargo-clean-all";
            rev = "v0.6.5";
            hash = "sha256-CJzjw/g0Ap7TKC2m+bVlH+/iCUOQITmE6HGvrNzWQ3o=";
          };
          cargoHash = "sha256-9Qv2/XacE82AtZCZS5vtSeVdnD6Ugs+Qn/EVevMndQM=";
        };
      };

      configuration =
        { pkgs, ... }:
        {
          nix = {
            settings = {
              experimental-features = "nix-command flakes";
              trusted-users = [
                "root"
                "simon"
              ];
              # We have the store on a case-sensitive APFS.
              use-case-hack = false;

              auto-optimise-store = true;

              min-free = 10737418240; # 10 GiB
              max-free = 53687091200; # 50 GiB
            };

            gc = {
              automatic = true;
              interval = [
                {
                  Weekday = 1;
                  Hour = 12;
                  Minute = 30;
                }
              ];
              options = "--delete-older-than 14d";
            };

            optimise = {
              automatic = true;
              # After the GC run above, so it scans fewer paths.
              interval = [
                {
                  Weekday = 1;
                  Hour = 13;
                  Minute = 30;
                }
              ];
            };
          };

          system = {
            configurationRevision = self.rev or self.dirtyRev or null;
            stateVersion = 6;

            # Finder's "Remove items from the Trash after 30 days".
            defaults.finder.FXRemoveOldTrashItems = true;

            # Spotlight has no nix-darwin option and its exclusion list lives in
            # a SIP-protected plist, so drive mdutil directly.
            activationScripts.postActivation.text = ''
              if [ -d /Volumes/Projects ]; then
                /usr/bin/mdutil -i off /Volumes/Projects >/dev/null
              fi
            '';
          };

          nixpkgs = {
            hostPlatform = system;
            config.allowUnfree = true;
            overlays = [ overlay ];
          };

          system.primaryUser = "simon";
          users.users.simon = {
            home = "/Users/simon";
          };

          networking.hostName = "itma-23001";

          environment.systemPackages = with pkgs; [
            claude-desktop
            firefox-bin
            google-chrome
            inkscape
            podman
            podman-compose
            podman-desktop
          ];

          programs = {
            _1password.enable = true;
            _1password-gui.enable = true;
          };

          security.pam.services.sudo_local.touchIdAuth = true;

          services.tailscale.enable = true;

          homebrew = {
            enable = true;

            onActivation = {
              autoUpdate = true;
              upgrade = true;
              cleanup = "zap";
            };

            taps = [
              "homebrew/core"
              {
                name = "inomotech/inomotech";
                trusted = true;
              }
            ];

            casks = [
              "cutter"
              "microsoft-teams"
              "windows-app"
              "zed@preview"
            ];
          };

          documentation.enable = false;
        };
    in
    {
      devShells.${system} = import ./devshells.nix {
        inherit pkgs;
        inherit (nixpkgs) lib;
      };

      formatter.${system} = treefmtEval.config.build.wrapper;

      checks.${system}.formatting = treefmtEval.config.build.check self;

      darwinConfigurations."itma-23001" = nix-darwin.lib.darwinSystem {
        modules = [
          configuration
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.users.simon = ./home.nix;

            # TEMP!
            home-manager.backupFileExtension = "hm-backup";
          }
        ];
      };
    };
}
