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

stdenvNoCC.mkDerivation rec {
  pname = "zed-delta";
  version = "0.21.0";

  src = fetchurl {
    url = "https://releases.delta.dev/releases/stable/${version}/macos/aarch64/Delta.app.zip";
    hash = "sha256-9T1DoNEyrGxlYVqhAthRcFgka9L3SPEKM9Qx7R0j2q0=";
  };

  nativeBuildInputs = [ unzip ];

  sourceRoot = ".";

  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -a Delta.app "$out/Applications"
    ln -s "$out/Applications/Delta.app/Contents/MacOS/delta" "$out/bin/delta"

    runHook postInstall
  '';

  passthru.updateScript = writeShellApplication {
    name = "zed-delta-update";
    runtimeInputs = [
      curl
      gnused
      jq
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Multiplayer workspace for coding agents from Zed Industries";
    homepage = "https://delta.dev";
    license = lib.licenses.unfree;
    mainProgram = "delta";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
