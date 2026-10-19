{
  lib,
  stdenvNoCC,
  cpio,
  curl,
  fetchurl,
  gnused,
  jq,
  libxml2,
  writeShellApplication,
  xar,
}:

stdenvNoCC.mkDerivation rec {
  pname = "windows-app";
  version = "11.4.4";

  src = fetchurl {
    url = "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Windows_App_${version}_installer.pkg";
    hash = "sha256-cAQSEOwcQMvMGRMBD7mn3n4rDI2fM2d3d1eJrmW8nKs=";
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

  passthru.updateScript = writeShellApplication {
    name = "windows-app-update";
    runtimeInputs = [
      curl
      gnused
      jq
      libxml2
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Microsoft client for remote Windows desktops and apps";
    homepage = "https://aka.ms/WindowsApp";
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
