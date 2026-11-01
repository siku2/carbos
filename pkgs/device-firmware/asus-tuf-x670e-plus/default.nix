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
  pname = "asus-tuf-x670e-plus-bios";
  version = "4005";

  src = fetchurl {
    url = "https://dlcdnets.asus.com/pub/ASUS/mb/BIOS/TUF-GAMING-X670E-PLUS-ASUS-${version}.ZIP";
    hash = "sha256-1LOGdTjEfg2WyjIW1cgmhG9AAuSBNY515d3FsjCdOQw=";
  };

  nativeBuildInputs = [ unzip ];

  # The unpack hook only knows lower case .zip.
  unpackPhase = ''
    unzip -qq $src
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out ${passthru.image}
    runHook postInstall
  '';

  passthru = {
    image = "TUF-GAMING-X670E-PLUS-ASUS-${version}.CAP";

    updateScript = writeShellApplication {
      name = "asus-tuf-x670e-plus-bios-update";
      runtimeInputs = [
        curl
        gnused
        jq
      ];
      text = builtins.readFile ./update.sh;
    };
  };

  meta = {
    description = "BIOS for the ASUS TUF GAMING X670E-PLUS, flashed with EZ Flash";
    homepage = "https://www.asus.com/motherboards-components/motherboards/tuf-gaming/tuf-gaming-x670e-plus/helpdesk_bios";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
}
