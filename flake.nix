{
  description = "System flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
    }:
    let
      configuration = { ... }: {
        nix.settings.experimental-features = "nix-command flakes";
        system.configurationRevision = self.rev or self.dirtyRev or null;
        system.stateVersion = 6;
        nixpkgs.hostPlatform = "aarch64-darwin";
        nixpkgs.config.allowUnfree = true;

        system.primaryUser = "simon";
        users.users.simon = {
          home = "/Users/simon";
        };

        networking.hostName = "itma-23001";

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
            "1password"
            "cutter"
            "docker-desktop"
            "firefox"
            "google-chrome"
            "inkscape"
            "microsoft-teams"
            "tailscale-app"
            "windows-app"
            "zed@preview"
          ];
        };
      };
    in
    {
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
