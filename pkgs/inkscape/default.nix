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

# The nixpkgs build crashes on tree row drag and drop on Darwin.
stdenvNoCC.mkDerivation rec {
  pname = "inkscape";
  version = "1.4.4";

  src = fetchurl {
    url = "https://media.inkscape.org/dl/resources/file/Inkscape-${version}_arm64.dmg";
    hash = "sha256-6sypSrAeWUZ83VRSooZ8NzRFD5pM+zNGlWzJsH808/E=";
  };

  nativeBuildInputs = [ undmg ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin"
    cp -a Inkscape.app "$out/Applications"
    ln -s "$out/Applications/Inkscape.app/Contents/MacOS/inkscape" "$out/bin/inkscape"

    runHook postInstall
  '';

  # Any change to the bundle breaks the code signature.
  dontFixup = true;

  passthru.updateScript = writeShellApplication {
    name = "inkscape-update";
    runtimeInputs = [
      curl
      gnused
      jq
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Vector graphics editor";
    homepage = "https://inkscape.org";
    license = lib.licenses.gpl3Plus;
    mainProgram = "inkscape";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
