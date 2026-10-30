{
  lib,
  stdenvNoCC,
  curl,
  fetchurl,
  gnused,
  jq,
  undmg,
  writeShellApplication,
}:

stdenvNoCC.mkDerivation rec {
  pname = "binaryninja-free";
  version = "6.0.10905";

  src = fetchurl {
    url = "https://github.com/Vector35/binaryninja-api/releases/download/stable/${version}/binaryninja_free_macosx.dmg";
    hash = "sha256-F4/uMj+YBrMO78gucdhQp4sqzUYreQq1ScEhxZ6iXuo=";
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

  passthru.updateScript = writeShellApplication {
    name = "binaryninja-free-update";
    runtimeInputs = [
      curl
      gnused
      jq
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Interactive decompiler, disassembler and debugger";
    homepage = "https://binary.ninja";
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
