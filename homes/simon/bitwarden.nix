{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataFile = "${config.home.homeDirectory}/.config/Bitwarden/data.json";

  # No policy file: these are the app's own state keys, which a Bitwarden
  # update can rename and silently stop applying.
  managed = {
    # rbw-agent serves ssh now.
    global_desktopSettings_sshAgentEnabled = false;

    global_theming_selection = "dark";

    global_environment_environment = {
      region = "Self-hosted";
      urls = {
        base = "https://vault.bg12.ch";
        api = null;
        identity = null;
        webVault = null;
        icons = null;
        notifications = null;
        events = null;
        keyConnector = null;
        send = null;
      };
    };
  };

  apply = pkgs.writeShellApplication {
    name = "bitwarden-settings";
    runtimeInputs = [
      pkgs.jq
      pkgs.procps
    ];
    text = builtins.readFile ./bitwarden-settings.sh;
  };
in
{
  home.activation.bitwardenSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    DATA_FILE=${lib.escapeShellArg dataFile} \
    MANAGED=${lib.escapeShellArg (builtins.toJSON managed)} \
    run ${lib.getExe apply}
  '';
}
