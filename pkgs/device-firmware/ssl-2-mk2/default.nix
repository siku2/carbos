{
  lib,
  stdenvNoCC,
  curl,
  fetchurl,
  gnused,
  jq,
  libxml2,
  unzip,
  writeShellApplication,
}:

stdenvNoCC.mkDerivation {
  pname = "ssl-2-mk2-firmware";
  # The firmware version for the device, not the version of the updater.
  version = "1.16";

  src = fetchurl {
    url = "https://s3.eu-west-2.amazonaws.com/zendesk.download.solidstatelogic.com/Interfaces/SSLAudioFirmwareUpdater_V1-5.zip";
    hash = "sha256-DMyh2r+zv91obVRV0wSPOrMNo/RsGSTy9oCy8Z5eeio=";
  };

  nativeBuildInputs = [
    libxml2
    unzip
  ];

  sourceRoot = ".";

  # The updater lists the image and version for each product ID. The SSL 2+
  # MkII (0x0009) gets the same image.
  installPhase = ''
    runHook preInstall
    cd */Windows/x64
    entry='//Device[@VID="0x31E9" and @PID="0x0008"]/Firmware'
    image=$(xmllint --xpath "string($entry)" SslUsbAudioDfu.xml)
    major=$(xmllint --xpath "string($entry/@MajorVersion)" SslUsbAudioDfu.xml)
    minor=$(xmllint --xpath "string($entry/@MinorVersion)" SslUsbAudioDfu.xml)
    if [ "$major.$minor" != "$version" ]; then
      echo "the updater has $major.$minor, not $version" >&2
      exit 1
    fi
    install -Dm644 "$image" $out/ssl2-mk2.bin
    runHook postInstall
  '';

  passthru.updateScript = writeShellApplication {
    name = "ssl-2-mk2-firmware-update";
    runtimeInputs = [
      curl
      gnused
      jq
      libxml2
      unzip
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Firmware for the SSL 2 MkII and SSL 2+ MkII audio interfaces";
    homepage = "https://support.solidstatelogic.com/hc/en-gb/articles/9645515893533";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
}
