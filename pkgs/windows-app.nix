{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  cpio,
}:

stdenvNoCC.mkDerivation rec {
  pname = "windows-app";
  version = "11.4.2";

  src = fetchurl {
    url = "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Windows_App_${version}_installer.pkg";
    hash = "sha256-5vl6hCKtyCZ8604XpIQZK9kLOsmy3yvEiSMUTzM3HU8=";
  };

  nativeBuildInputs = [
    xar
    cpio
  ];

  # Only the app itself. The installer also bundles Microsoft AutoUpdate.
  unpackPhase = ''
    runHook preUnpack
    xar -xf "$src" com.microsoft.rdc.macos.pkg/Payload
    gzip -dc com.microsoft.rdc.macos.pkg/Payload | cpio -idm
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications"
    cp -a "Windows App.app" "$out/Applications"

    runHook postInstall
  '';

  dontFixup = true;

  meta = {
    description = "Microsoft client for remote Windows desktops and apps";
    homepage = "https://aka.ms/WindowsApp";
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
