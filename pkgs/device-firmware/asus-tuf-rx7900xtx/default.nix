{
  lib,
  stdenvNoCC,
  curl,
  fetchurl,
  fwupd,
  gnused,
  jq,
  unrar,
  unzip,
  writeShellApplication,
}:

# The ASUS TUF RX 7900 XTX VBIOS update tool. ASUS only ships it for Windows,
# but fwupd flashes the images inside. The card has a ROM for each position of
# its BIOS switch.
stdenvNoCC.mkDerivation rec {
  pname = "asus-tuf-rx7900xtx-vbios";
  version = "022.001.002.020.000001";

  src = fetchurl {
    url = "https://dlcdnets.asus.com/pub/ASUS/Graphic%20Card/AMD_VBIOS/AMD_Radeon_RX_7900_XTX_BIOS_Update_Tool.zip";
    hash = "sha256-GwJsaxOa4fVl7QJ11LHo48kjEYjKfyn4+Q/+kVvKIOk=";
  };

  nativeBuildInputs = [
    unrar
    unzip
  ];

  # The zip holds a WinRAR self-extracting exe.
  unpackPhase = ''
    unzip -qq $src
    unrar e -inul ./*.exe '*.rom'
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 ./*P.rom $out/p.rom
    install -Dm644 ./*Q.rom $out/q.rom
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ fwupd ];
  installCheckPhase = ''
    runHook preInstallCheck
    export FWUPD_LOCALSTATEDIR=$TMPDIR/var CACHE_DIRECTORY=$TMPDIR/cache
    for rom in $out/*.rom; do
      actual=$(fwupdtool firmware-parse "$rom" amd-gpu-psp | sed -n 's|^ *<version>\(.*\)</version>$|\1|p' | sort -u)
      if [ "$actual" != "$version" ]; then
        echo "$rom is version $actual, not $version." >&2
        exit 1
      fi
    done
    runHook postInstallCheck
  '';

  passthru.updateScript = writeShellApplication {
    name = "asus-tuf-rx7900xtx-vbios-update";
    runtimeInputs = [
      curl
      fwupd
      gnused
      jq
      unrar
      unzip
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "VBIOS for the ASUS TUF Gaming Radeon RX 7900 XTX";
    homepage = "https://www.asus.com/motherboards-components/graphics-cards/tuf-gaming/tuf-rx7900xtx-o24g-gaming/helpdesk_bios";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
}
