{ lib, stdenvNoCC }:
let
  plugin =
    dir:
    let
      manifest = lib.importJSON (dir + "/plugin.json");
    in
    stdenvNoCC.mkDerivation {
      pname = "dms-plugin-${manifest.id}";
      inherit (manifest) version;
      src = dir;

      dontBuild = true;
      installPhase = ''
        runHook preInstall
        cp -r . $out
        runHook postInstall
      '';

      passthru = { inherit manifest; };
    };

  dirs = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./.));
in
# Keyed by the id in each manifest, which is also what DMS uses.
lib.listToAttrs (
  map (
    name:
    let
      package = plugin (./. + "/${name}");
    in
    lib.nameValuePair package.manifest.id package
  ) dirs
)
