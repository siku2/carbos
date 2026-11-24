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
  version = "26304.1206.5384.1209";

  src = fetchurl {
    url = "https://statics.teams.cdn.office.net/production-osx/${version}/MicrosoftTeams.pkg";
    hash = "sha256-UjwXOULxN134wo/pchcRMTy1ZFYlehgCU6gL8ndIvoM=";
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
