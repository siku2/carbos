{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  # See https://downloads.claude.ai/releases/darwin/universal/RELEASES.json
  version = "2.9939.4";
  commit = "a166d8a7c640e65ad825ebfb99d74ccbb9c8940d";
in
stdenvNoCC.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/releases/darwin/universal/${version}/Claude-${commit}.zip";
    hash = "sha256-k8xjfMKzi7eMV64HLdgXubF/qMsBqu3+JFTmxgSYwo8=";
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

  meta = {
    description = "Desktop application for Claude";
    homepage = "https://claude.com/download";
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
