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
  version = "26225.1708.5124.9749";

  src = fetchurl {
    url = "https://statics.teams.cdn.office.net/production-osx/${version}/MicrosoftTeams.pkg";
    hash = "sha256-s7kTIaQKH7MK7nuY3msuVEvpNLN07MJLHK8fJ9YQJ58=";
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
