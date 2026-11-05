{
  config,
  lib,
  pkgs,
  ...
}:
let
  secretspecManifest = ../../secretspec.toml;
  secretspec = lib.getExe pkgs.secretspec;

  keyPath = "${config.xdg.dataHome}/atuin/key";

  seedKey = pkgs.writeShellApplication {
    name = "atuin-seed-key";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./atuin-seed-key.sh;
  };

  seedFromKeyring = pkgs.writeShellScript "atuin-key" ''
    export KEY_PATH=${keyPath}
    exec ${secretspec} --file ${secretspecManifest} run \
      --scope atuin \
      --caller atuin-key \
      --reason "atuin needs its sync key to read the synced history" \
      -- ${lib.getExe seedKey}
  '';

  fishInit = pkgs.runCommand "atuin-init.fish" {
    nativeBuildInputs = [ pkgs.writableTmpDirAsHomeHook ];
  } "${lib.getExe config.programs.atuin.package} init fish > $out";
in
{
  programs.atuin = {
    enable = true;
    package = pkgs.atuin;
    # Atuin generates a random key if none exists, so wait for the seeded one.
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableZshIntegration = false;
    settings = {
      update_check = false;
      enter_accept = true;
      filter_mode_shell_up_key_binding = "workspace";
      inline_height = 30;
      inline_height_shell_up_key_binding = 10;
      show_tabs = false;
      sync = {
        records = true;
      };
    };
  };

  programs.fish.interactiveShellInit = ''
    if test -e ${keyPath}
      source ${fishInit}
    end
  '';

  # Without the key a new machine starts its own history stream.
  systemd.user.services.atuin-key = {
    Unit = {
      Description = "Seed the atuin sync key";
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${seedFromKeyring}";
      # The keyring may come up after us. A key mismatch needs a human.
      Restart = "on-failure";
      RestartSec = 15;
      RestartPreventExitStatus = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };

  launchd.agents.atuin-key = {
    enable = true;
    config = {
      ProgramArguments = [ "${seedFromKeyring}" ];
      RunAtLoad = true;
    };
  };
}
