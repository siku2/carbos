{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.carbos.installer.bundle = lib.mkOption {
    type = lib.types.attrs;
    description = "The rev, flake source and per-host data from installer/bundle.nix.";
  };

  config = {
    console = {
      earlySetup = true;
      font = "ter-v24n";
      packages = [ pkgs.terminus_font ];
    };

    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];

    environment.systemPackages = [
      (pkgs.callPackage ./package.nix { inherit (config.carbos.installer) bundle; })
      pkgs.git
      pkgs.vim
    ];

    # carbos-install waits for this before it touches the disk.
    systemd.services.carbos-verify = {
      description = "Verify integrity of the bundled Nix store";
      after = [ "register-nix-paths.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe' config.nix.package "nix-store"} --verify --check-contents";
      };
    };

    programs.bash.loginShellInit = ''
      if [ "$(tty)" = /dev/tty1 ]; then
        carbos-install
      fi
    '';
  };
}
