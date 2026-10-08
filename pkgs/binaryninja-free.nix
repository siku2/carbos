{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:

stdenvNoCC.mkDerivation rec {
  pname = "binaryninja-free";
  version = "6.0.10601";

  src = fetchurl {
    url = "https://github.com/Vector35/binaryninja-api/releases/download/stable/${version}/binaryninja_free_macosx.dmg";
    hash = "sha256-sjqlwJJ+DJCsOn3TL0nXMt2lKbD2TO9mnB3bIpMuaMI=";
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -a "Binary Ninja.app" "$out/Applications"

    runHook postInstall
  '';

  # Any change to the bundle breaks the code signature.
  dontFixup = true;

  meta = {
    description = "Interactive decompiler, disassembler and debugger";
    homepage = "https://binary.ninja";
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
