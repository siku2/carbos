{ inputs, pkgs, ... }:
{
  imports = [
    ./tailscale.nix
    inputs.lux.darwinModules.default
  ]
  ++ (with inputs.self.modules.darwin; [
    agents
    dev
    git
    nix
    remote
    shell
    system
    vault
  ]);

  services.lx = {
    enable = true;
    memory = 8192;
    shares = [
      "/Users"
      "/Volumes/Projects"
    ];
  };

  pmset = {
    enable = true;
    ac.sleep = 0;
  };

  nixpkgs.hostPlatform = "aarch64-darwin";

  nix = {
    settings = {
      trusted-users = [
        "root"
        "simon"
      ];
      # We have the store on a case-sensitive APFS.
      use-case-hack = false;

      min-free = 10737418240; # 10 GiB
      max-free = 53687091200; # 50 GiB

      max-jobs = 6;
      cores = 4;

      warn-large-path-threshold = "1G";
    };
  };

  system = {
    stateVersion = 6;

    defaults = {
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
    zed-delta
  ];

  carbos.user.email = "simon.berger@inomotech.com";
  carbos.vault.backend = "1password";

  home-manager.users.simon = {
    imports = [ ./home ];
    home.stateVersion = "26.05";
  };
}
