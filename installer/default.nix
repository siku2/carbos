{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot.initrd.systemd.enable = lib.mkForce false;

  boot.kernelParams = lib.mkForce [
    "console=ttyS0,115200"
    "console=tty0"
    "panic=30"
    "boot.panic_on_fail"
  ];

  # kexec hands the kernel no EFI framebuffer, so nothing shows until i915
  # binds. Load it in the initrd for a console as early as possible.
  boot.initrd.kernelModules = [ "i915" ];

  hardware.enableRedistributableFirmware = lib.mkForce true;

  networking.hostName = "carbos-installer";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages =
    (with pkgs; [
      curl
      disko
      git
      nixos-install-tools
      vim
    ])
    ++ [
      (pkgs.writeShellScriptBin "carbos-install" (builtins.readFile ./carbos-install.sh))
    ];

  systemd.services.carbos-verify = {
    description = "Verify integrity of the bundled Nix store";
    after = [ "register-nix-paths.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      echo "carbos-verify: hashing every store path, this takes a minute"
      if ${lib.getExe' config.nix.package "nix-store"} --verify --check-contents; then
        echo "carbos-verify: PASS - store is intact"
      else
        echo "carbos-verify: FAIL - store is corrupt in memory"
      fi
    '';
  };

  users.motd = ''

    Run carbos-install to install carbos on this machine.

  '';

  system.stateVersion = "26.05";
}
