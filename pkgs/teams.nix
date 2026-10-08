{ unstable, fetchurl }:

# nixpkgs lags behind the releases by months and its fixup phase breaks the
# code signature.
unstable.teams.overrideAttrs rec {
  version = "26225.1708.5124.9749";

  src = fetchurl {
    url = "https://statics.teams.cdn.office.net/production-osx/${version}/MicrosoftTeams.pkg";
    hash = "sha256-s7kTIaQKH7MK7nuY3msuVEvpNLN07MJLHK8fJ9YQJ58=";
  };

  dontFixup = true;
}
