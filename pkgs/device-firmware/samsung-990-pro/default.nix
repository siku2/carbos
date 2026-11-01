{
  lib,
  stdenvNoCC,
  binutils,
  cpio,
  curl,
  fetchurl,
  gnused,
  jq,
  nodejs-slim,
  p7zip,
  unzip,
  writeShellApplication,
}:

# Samsung's ISO boots Linux and runs fumagician, which decrypts the images and
# sends one with the standard NVMe firmware commands. This does the decryption
# at build time. The key is a base64 string in the fumagician binary.
stdenvNoCC.mkDerivation rec {
  pname = "samsung-990-pro-firmware";
  version = "8B2QJXD7";

  src = fetchurl {
    url = "https://download.semiconductor.samsung.com/resources/software-resources/Samsung_SSD_990_PRO_${version}.iso";
    hash = "sha256-8FUI8yKJYPwVAf5aJ9OoJjdzMq/IwCGqxESHyP0ck9U=";
  };

  nativeBuildInputs = [
    binutils
    cpio
    nodejs-slim
    p7zip
    unzip
  ];

  unpackPhase = ''
    7z x -y -oiso $src initrd >/dev/null
    mkdir initrd
    gzip -dc iso/initrd | (cd initrd && cpio -id --quiet 'root/fumagician/*')
  '';

  buildPhase = ''
    runHook preBuild
    tool=initrd/root/fumagician
    key=$(strings -n 44 $tool/fumagician | grep -m1 -xE '[A-Za-z0-9+/]{43}=')
    decrypt() { node ${./decrypt.ts} "$key" "$1" "$2"; }

    decrypt $tool/DSRD.enc DSRD.xml
    decrypt $tool/${version}.enc images.zip
    # The archive repeats entries, all copies are identical.
    unzip -o -qq images.zip -d inner
    mkdir images
    for enc in inner/*.enc; do
      decrypt $enc images/$(basename $enc .enc).bin
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 -t $out DSRD.xml images/*.bin
    runHook postInstall
  '';

  passthru.updateScript = writeShellApplication {
    name = "samsung-990-pro-firmware-update";
    runtimeInputs = [
      curl
      gnused
      jq
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Firmware for the Samsung 990 PRO, one image per hardware variant";
    homepage = "https://semiconductor.samsung.com/consumer-storage/support/tools/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryFirmware ];
    platforms = lib.platforms.linux;
  };
}
