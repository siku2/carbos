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
  version = "5.1231.2";
  commit = "26912242b6649f3e503e012d9b7b9367d09c68e4";
in
stdenvNoCC.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/releases/darwin/universal/${version}/Claude-${commit}.zip";
    hash = "sha256-50z+yY0lYIEqX+kbsH/konfO/qcdQDn2vzsd4zhGJAo=";
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
