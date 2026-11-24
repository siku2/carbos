{ lib, stdenvNoCC }:

# Read from the printer over ISP. See hosts/nixos/filamancer/README.md.
stdenvNoCC.mkDerivation {
  pname = "profi3dmaker-firmware";
  version = "1.3.22T";

  src = ./profi3dmaker.bin;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 $src $out/profi3dmaker.bin
    runHook postInstall
  '';

  meta = {
    description = "Stock 3Dfactories Sprinter firmware for the Profi3DMaker printer";
    homepage = "https://github.com/kliment/Sprinter";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.all;
  };
}
