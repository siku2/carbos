{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "rlbot-server";
  version = "5.0.0-rc17";

  src = fetchurl {
    url = "https://github.com/RLBot/core/releases/download/v${finalAttrs.version}/RLBotServer";
    hash = "sha256-Rvi3BUuYYio3F/nJ/nvlIHhBzkt6jrTNMcU3T5X2Vtw=";
    executable = true;
  };

  dontUnpack = true;

  nativeBuildInputs = [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/RLBotServer
    runHook postInstall
  '';

  meta = {
    description = "RLBot v5 server";
    homepage = "https://github.com/RLBot/core";
    # The bridge to Rocket League is closed source.
    license = with lib.licenses; [
      mit
      unfreeRedistributable
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "RLBotServer";
  };
})
