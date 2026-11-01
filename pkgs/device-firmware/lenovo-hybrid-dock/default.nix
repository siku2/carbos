{
  lib,
  stdenvNoCC,
  curl,
  fetchurl,
  fwupd,
  gnused,
  innoextract,
  jq,
  writeShellApplication,
}:

# The ThinkPad Hybrid USB-C with USB-A Dock (40AF) update tool. Lenovo only
# ships it for Windows, but fwupd flashes the images inside.
stdenvNoCC.mkDerivation rec {
  pname = "lenovo-hybrid-dock-firmware";
  version = "1.0.42";

  src = fetchurl {
    url = "https://download.lenovo.com/pccbbs/mobiles/fhybd1042_1.exe";
    hash = "sha256-i6D2KpPmGpy8RjaEBalVKfFlg7i/QoTbB0+H+etxkyU=";
  };

  nativeBuildInputs = [ innoextract ];

  unpackPhase = ''
    innoextract --silent --extract $src
  '';

  # The VL822 and VL105 images are for a later hardware revision.
  installPhase = ''
    runHook preInstall
    tool='code$GetExtractPath$'
    install -Dm644 "$tool"/VL_ISP/Binfile/VL820_Q8_*_Tier1_*.bin $out/vl820-tier1.bin
    install -Dm644 "$tool"/VL_ISP/Binfile/VL820_Q7_*_Tier2_*.bin $out/vl820-tier2.bin
    install -Dm644 "$tool"/CY_ISP/CCG4_FW1.cyacd $out/ccg4-fw1.cyacd
    install -Dm644 "$tool"/CY_ISP/CCG4_FW2.cyacd $out/ccg4-fw2.cyacd
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ fwupd ];
  installCheckPhase = ''
    runHook preInstallCheck
    export FWUPD_LOCALSTATEDIR=$TMPDIR/var CACHE_DIRECTORY=$TMPDIR/cache
    check() {
      actual=$(fwupdtool firmware-parse "$out/$1" "$2" | sed -n 's|^ *<version>\(.*\)</version>$|\1|p' | head -1)
      if [ "$actual" != "$3" ]; then
        echo "$1 is version $actual, not $3. Update passthru.versions." >&2
        exit 1
      fi
    }
    check vl820-tier1.bin vli-usbhub ${passthru.versions.tier1}
    check vl820-tier2.bin vli-usbhub ${passthru.versions.tier2}
    check ccg4-fw1.cyacd ccgx ${passthru.versions.pd}
    check ccg4-fw2.cyacd ccgx ${passthru.versions.pd}
    runHook postInstallCheck
  '';

  passthru = {
    # What the devices report once flashed.
    versions = {
      tier1 = "55.63";
      tier2 = "55.64";
      pd = "0.2.78";
    };

    updateScript = writeShellApplication {
      name = "lenovo-hybrid-dock-firmware-update";
      runtimeInputs = [
        curl
        gnused
        jq
      ];
      text = builtins.readFile ./update.sh;
    };
  };

  meta = {
    description = "Firmware for the ThinkPad Hybrid USB-C with USB-A Dock";
    homepage = "https://support.lenovo.com/downloads/ds504448";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
}
