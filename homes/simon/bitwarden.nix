{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataFile = "${config.home.homeDirectory}/.config/Bitwarden/data.json";

  # The desktop app has no policy file and no CLI for its settings, so these
  # keys are written straight into its state. The names come from the app
  # bundle and are not a public interface, so a Bitwarden update can rename
  # them. If that happens these values stop being applied and the app falls
  # back to whatever its UI last stored.
  #
  # Key layout is "global_<stateDefinition>_<key>". The environment is one
  # object, not a key per field, and the app writes every url field, so match
  # that shape exactly.
  managed = {
    global_desktopSettings_sshAgentEnabled = true;

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

    # The app runs as "electron", so match its app.asar path rather than a name.
    if ${lib.getExe' pkgs.procps "pgrep"} -f "/opt/Bitwarden/resources/app.asar" > /dev/null; then
      echo "bitwarden is running, leaving its settings alone" >&2
      exit 0
    fi

    mkdir -p "$(dirname ${dataFile})"
    [ -f ${dataFile} ] || echo '{}' > ${dataFile}

    tmp=$(mktemp ${dataFile}.XXXXXX)
    trap 'rm -f "$tmp"' EXIT
    ${lib.getExe pkgs.jq} --argjson managed ${lib.escapeShellArg (builtins.toJSON managed)} \
      '. * $managed' ${dataFile} > "$tmp"
    mv "$tmp" ${dataFile}
    trap - EXIT
  '';
in
{
  home.activation.bitwardenSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${apply}
  '';
}
