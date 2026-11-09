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

# The Lightspeed receiver inside the POWERPLAY mat (USB 046d:c53a). G HUB
# ships its image in a depot that details.json lists, like the G903 one.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "logitech-powerplay-receiver-firmware";
  version = "40.3.14";

  src = fetchurl {
    url = "https://updates.ghub.logitechg.com/depots/21b7da7a-c86d-4fda-beb3-d049338b7c78/c53a_dfu.depot";
    hash = "sha256-Xdq1CQfxURRojMvF1TV0Vkca/kj9BlwXdciaR0vRn84=";
  };

  nativeBuildInputs = [
    jq
    nodejs-slim
  ];

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    node ${../ghub-depot.ts} $src depot
    version=$(jq -r '.contents[0].version' depot/dfu.json)
    if [ "$version" != "${finalAttrs.version}" ]; then
      echo "the depot has $version, not ${finalAttrs.version}" >&2
      exit 1
    fi
    install -Dm644 depot/c53a_v*.shex $out/c53a.shex
    runHook postInstall
  '';

  passthru = {
    # The version as fwupd reads it from the receiver.
    deviceVersion =
      let
        parts = lib.splitString "." finalAttrs.version;
        pad = width: lib.fixedWidthString width "0";
      in
      "RQR${lib.elemAt parts 0}.${pad 2 (lib.elemAt parts 1)}_B${pad 4 (lib.elemAt parts 2)}";

    updateScript = writeShellApplication {
      name = "logitech-powerplay-receiver-firmware-update";
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
    description = "Firmware for the Lightspeed receiver in the Logitech POWERPLAY mat";
    homepage = "https://www.logitechg.com/innovation/g-hub.html";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
})
