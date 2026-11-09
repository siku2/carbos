{
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:
stdenv.mkDerivation {
  pname = "logitech-hidpp";
  inherit (kernel) version;

  inherit (kernel) src;
  unpackPhase = ''
    mkdir source
    cd source
    tar -xf $src --strip-components=3 --wildcards \
      '*/drivers/hid/hid-logitech-hidpp.c' \
      '*/drivers/hid/hid-ids.h' \
      '*/drivers/hid/usbhid/usbhid.h'
    cp ${./Kbuild} Kbuild
  '';

  patches = [ ./leds.patch ];
  patchFlags = [ "-p3" ];

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)"
    "INSTALL_MOD_PATH=$(out)"
  ];

  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];
}
