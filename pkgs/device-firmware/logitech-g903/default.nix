{
  lib,
  stdenvNoCC,
  curl,
  fetchurl,
  gnused,
  jq,
  nodejs-slim,
  writeShellApplication,
}:

# G HUB ships the image in a depot that its update pipeline lists in
# details.json. The depot URL changes with each G HUB build.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "logitech-g903-firmware";
  version = "07.02.13";

  src = fetchurl {
    url = "https://updates.ghub.logitechg.com/depots/5af237fa-bef0-482a-a13f-23d5d1b1ac55/g903_dfu.depot";
    hash = "sha256-XsxemRGJpfC14tt+UXqqaOIyC1bUGRHqa3E+mWPIy74=";
  };

  nativeBuildInputs = [
    jq
    nodejs-slim
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    node ${./depot.ts} $src depot
    version=$(jq -r '.contents[0].version' depot/dfu.json)
    if [ "$version" != "${finalAttrs.version}" ]; then
      echo "the depot has $version, not ${finalAttrs.version}" >&2
      exit 1
    fi
    install -Dm644 depot/g903_v*.dfu $out/g903.dfu
    runHook postInstall
  '';

  passthru = {
    # The version as fwupd reads it from the mouse.
    deviceVersion =
      let
        parts = lib.splitString "." finalAttrs.version;
      in
      "MPM${lib.elemAt parts 0}.${lib.elemAt parts 1}_B${
        lib.fixedWidthString 4 "0" (lib.elemAt parts 2)
      }";

    updateScript = writeShellApplication {
      name = "logitech-g903-firmware-update";
      runtimeInputs = [
        curl
        gnused
        jq
        nodejs-slim
      ];
      text = builtins.readFile ./update.sh;
    };
  };

  meta = {
    description = "Firmware for the Logitech G903 mouse, flashed over its USB cable";
    homepage = "https://www.logitechg.com/innovation/g-hub.html";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
})
