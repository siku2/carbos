{
  bundle,
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
    "loglevel=3"
    "panic=30"
    "boot.panic_on_fail"
  ];

  # kexec hands the kernel no EFI framebuffer, so nothing shows until i915
  # binds. Load it in the initrd for a console as early as possible.
  boot.initrd.kernelModules = [ "i915" ];

  hardware.enableRedistributableFirmware = lib.mkForce true;

  console = {
    earlySetup = true;
    font = "ter-v24n";
    packages = [ pkgs.terminus_font ];
  };

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
      gptfdisk
      gum
      jq
      nix-output-monitor
      parted
      nixos-install-tools
      vim
    ])
    ++ [
      (pkgs.writeShellScriptBin "carbos-install" (builtins.readFile ./carbos-install.sh))
    ];

  environment.etc = {
    "carbos/hosts.json".text = builtins.toJSON bundle.hosts;
    "carbos/rev".text = bundle.rev;
    "carbos/source".source = bundle.source;
  };

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

  system.stateVersion = "26.05";
}
