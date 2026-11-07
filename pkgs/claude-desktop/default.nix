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
  version = "4.23118.0";
  commit = "8175c354eda704cea00fdeddfa69cea329dd321a";
in
stdenvNoCC.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/releases/darwin/universal/${version}/Claude-${commit}.zip";
    hash = "sha256-W4/u49oEjia7sppdYB6XA09nSsO3b30CN3UcRtYDSyM=";
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
