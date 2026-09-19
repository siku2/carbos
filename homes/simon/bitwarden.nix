{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataFile = "${config.home.homeDirectory}/.config/Bitwarden/data.json";

  # There is no policy file, so these go straight into the app's own state.
  # Keys are "global_<stateDefinition>_<key>" and a Bitwarden update can rename
  # them, in which case they silently stop applying.
  managed = {
    global_desktopSettings_sshAgentEnabled = true;

    # --autostart below only hides the window when this is on.
    global_desktopSettings_runInBackground = true;

    # Otherwise the app writes its own autostart entry with a stale store path.
    global_desktopSettings_openAtLogin = false;

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

  apply = pkgs.writeShellScript "bitwarden-settings" ''
    set -eu

    # The process is named "electron", so match on the bundle path.
    if ${lib.getExe' pkgs.procps "pgrep"} -f "/opt/Bitwarden/resources/app.asar" > /dev/null; then
      echo "bitwarden is running, leaving its settings alone" >&2
      exit 0
    fi

    mkdir -p "$(dirname ${dataFile})"
    [ -f ${dataFile} ] || echo '{}' > ${dataFile}

    tmp=$(mktemp ${dataFile}.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    ${lib.getExe pkgs.jq} --argjson managed ${lib.escapeShellArg (builtins.toJSON managed)} '
      . * $managed
      | if .global_account_activeAccountId then
          .["user_" + .global_account_activeAccountId + "_desktopSettings_sshAgentRememberAuthorizations"] = "never"
        else . end
    ' ${dataFile} > "$tmp"
    mv "$tmp" ${dataFile}
    trap - EXIT
  '';
in
{
  home.activation.bitwardenSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${apply}
  '';

  systemd.user.services.bitwarden = {
    Unit = {
      Description = "Bitwarden desktop";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.bitwarden-desktop} --autostart";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
