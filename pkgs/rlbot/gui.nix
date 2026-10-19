{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  glib,
  glib-networking,
  gtk3,
  libsoup_3,
  webkitgtk_4_1,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "rlbot-gui";
  version = "beat24";

  src = fetchurl {
    url = "https://github.com/RLBot/gui/releases/download/${finalAttrs.version}/rlbotgui";
    hash = "sha256-qQfEC/6TMACoxZt0CPeIJTZCsQvOAPKosDhBxK1tAQM=";
    executable = true;
  };

  icon = fetchurl {
    url = "https://raw.githubusercontent.com/RLBot/gui/${finalAttrs.version}/build/appicon.png";
    hash = "sha256-MoW7GmVUtVuoeMk6Rrh+X5Eul46LXt9f4QSO/RATjZw=";
  };

  dontUnpack = true;

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
  ];

  # glib-networking provides TLS for the botpack downloads.
  buildInputs = [
    glib
    glib-networking
    gtk3
    libsoup_3
    webkitgtk_4_1
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/rlbotgui
    install -Dm644 $icon $out/share/pixmaps/rlbot.png
    runHook postInstall
  '';

  meta = {
    description = "GUI for RLBot v5";
    homepage = "https://github.com/RLBot/gui";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "rlbotgui";
  };
})
