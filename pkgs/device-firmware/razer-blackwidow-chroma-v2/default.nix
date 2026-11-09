{
  lib,
  stdenvNoCC,
  curl,
  fetchurl,
  gnused,
  jq,
  libarchive,
  nodejs-slim,
  razer-kbd-flash,
  writeShellApplication,
}:

# Razer's updater is a RAR self-extractor. Its DeviceUpdater.resources holds
# the image as Intel HEX, one .NET resource string per line.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "razer-blackwidow-chroma-v2-firmware";
  version = "1.01.00";

  src = fetchurl {
    url = "https://dl.razerzone.com/drivers/BlackWidow%20Chroma%20V2/win/BlackWidow%20Chroma%20V2_FirmwareUpdater_v${finalAttrs.version}_r2.exe";
    hash = "sha256-nI5GjmUxViowHYSfDm28hgnSdJwv14Qp7y8j1o5ZGHE=";
  };

  nativeBuildInputs = [
    libarchive
    nodejs-slim
  ];

  unpackPhase = ''
    bsdtar -xf $src DeviceUpdater.resources
  '';

  installPhase = ''
    runHook preInstall
    version=$(node ${./resources.ts} DeviceUpdater.resources image.hex)
    if [ "$version" != "${finalAttrs.version}" ]; then
      echo "the updater has $version, not ${finalAttrs.version}" >&2
      exit 1
    fi
    install -Dm644 image.hex $out/bwc2.hex
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ razer-kbd-flash ];
  installCheckPhase = ''
    runHook preInstallCheck
    razer-kbd-flash check $out/bwc2.hex | grep -qx "version: ${finalAttrs.version}"
    runHook postInstallCheck
  '';

  passthru.updateScript = writeShellApplication {
    name = "razer-blackwidow-chroma-v2-firmware-update";
    runtimeInputs = [
      curl
      gnused
      jq
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Firmware for the Razer BlackWidow Chroma V2 keyboard";
    homepage = "https://mysupport.razer.com/app/answers/detail/a_id/4661";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
})
