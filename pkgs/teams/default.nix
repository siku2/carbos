{
  teams,
  curl,
  fetchurl,
  gnused,
  jq,
  libxml2,
  writeShellApplication,
}:

# nixpkgs lags behind the releases by months and its fixup phase breaks the
# code signature.
teams.overrideAttrs (old: rec {
  version = "26276.505.5234.9924";

  src = fetchurl {
    url = "https://statics.teams.cdn.office.net/production-osx/${version}/MicrosoftTeams.pkg";
    hash = "sha256-vQKcICOpQ9x2yaA0EMkfBti5LAcRXa+XY9W5R1qrqHw=";
  };

  dontFixup = true;

  passthru = (old.passthru or { }) // {
    updateScript = writeShellApplication {
      name = "teams-update";
      runtimeInputs = [
        curl
        gnused
        jq
        libxml2
      ];
      text = builtins.readFile ./update.sh;
    };
  };
})
