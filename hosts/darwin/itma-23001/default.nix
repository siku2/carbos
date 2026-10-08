{ inputs, pkgs, ... }:
{
  imports = with inputs.self.modules.darwin; [
    packages
    unstable
  ];

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
  };

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
    configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
    stateVersion = 6;
    primaryUser = "simon";

    defaults = {
      dock = {
        autohide = true;
        # Never show on hover. Cmd-Opt-D still toggles it.
        autohide-delay = 1000.0;
        show-recents = false;
        mru-spaces = false;
      };

      # Finder's "Remove items from the Trash after 30 days".
      finder.FXRemoveOldTrashItems = true;

      CustomUserPreferences."com.microsoft.autoupdate2" = {
        HowToCheck = "Manual";
        StartDaemonOnAppLaunch = false;
      };
    };

    # Spotlight has no nix-darwin option and its exclusion list lives in
    # a SIP-protected plist, so drive mdutil directly.
    activationScripts.postActivation.text = ''
      if [ -d /Volumes/Projects ]; then
        /usr/bin/mdutil -i off /Volumes/Projects >/dev/null
      fi
    '';
  };

  users.users.simon.home = "/Users/simon";

  networking.hostName = "itma-23001";

  environment.systemPackages = with pkgs; [
    binaryninja-free
    chatgpt
    claude-desktop
    cutter
    # "unwrapped" to preserve signature for 1password.
    firefox-bin-unwrapped
    google-chrome
    inkscape
    podman
    podman-compose
    podman-desktop
    teams
    windows-app
  ];

  programs = {
    _1password.enable = true;
    _1password-gui.enable = true;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  services.tailscale.enable = true;
  environment.etc."resolver/inomo.tech".text = "nameserver 100.100.100.100";

  documentation.enable = false;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs;
    };
    users.simon = ./home;
  };
}
