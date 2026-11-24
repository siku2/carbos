{
  lib,
  stdenvNoCC,
  curl,
  fetchurl,
  gnused,
  jq,
  unzip,
  writeShellApplication,
}:

let
  version = "7.37095.0";
  commit = "bc368c812ec26d3a5740519cc4d5cb69bbe43025";
in
stdenvNoCC.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/releases/darwin/universal/${version}/Claude-${commit}.zip";
    hash = "sha256-gAgGVWys7Oa9rLufOu8YSantjW/C7g6y7YgaCY0JTqs=";
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";

  # Any change to the bundle, like patchShebangs on the browser shim, breaks
  # the code signature.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -a Claude.app "$out/Applications"

    runHook postInstall
  '';

  passthru.updateScript = writeShellApplication {
    name = "claude-desktop-update";
    runtimeInputs = [
      curl
      gnused
      jq
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Desktop application for Claude";
    homepage = "https://claude.com/download";
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
