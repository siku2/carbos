{
  config,
  lib,
  pkgs,
  ...
}:
let
  secretspecManifest = ../../secretspec.toml;
  secretspec = lib.getExe pkgs.unstable.secretspec;

  keyPath = "${config.xdg.dataHome}/atuin/key";

  seedKey = pkgs.writeShellApplication {
    name = "atuin-seed-key";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./atuin-seed-key.sh;
  };
in
{
  programs.atuin = {
    enable = true;
    package = pkgs.unstable.atuin;
    settings = {
      update_check = false;
      enter_accept = true;
      filter_mode_shell_up_key_binding = "session";
      inline_height = 30;
      inline_height_shell_up_key_binding = 10;
      show_tabs = false;
      sync = {
        records = true;
      };
    };
  };

  # Without the key a new machine starts its own history stream.
  systemd.user.services.atuin-key = {
    Unit = {
      Description = "Seed the atuin sync key";
      ConditionPathExists = "!${keyPath}";
    };
    Service = {
      Type = "oneshot";
      Environment = [ "KEY_PATH=${keyPath}" ];
      ExecStart = ''
        ${secretspec} --file ${secretspecManifest} run \
          --scope atuin \
          --caller atuin-key \
          --reason "atuin needs its sync key to read the synced history" \
          -- ${lib.getExe seedKey}
      '';
    };
    Install.WantedBy = [ "default.target" ];
  };
}
