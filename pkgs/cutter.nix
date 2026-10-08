{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation rec {
  pname = "cutter";
  version = "2.5.0";

  src = fetchurl {
    url = "https://github.com/rizinorg/cutter/releases/download/v${version}/Cutter-v${version}-macOS-arm64.dmg";
    hash = "sha256-7AhHdInLf3adQSHlCEsJExsCtqgBrHotWJamfocZNFI=";
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -a Cutter.app "$out/Applications"

    runHook postInstall
  '';

  # Any change to the bundle breaks the code signature.
  dontFixup = true;

  meta = {
    description = "Reverse engineering platform powered by Rizin";
    homepage = "https://cutter.re";
    license = lib.licenses.gpl3Plus;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
