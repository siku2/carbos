{
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:
stdenv.mkDerivation {
  pname = "nzxt-smart2";
  inherit (kernel) version;

  inherit (kernel) src;
  unpackPhase = ''
    mkdir source
    cd source
    tar -xf $src --strip-components=3 --wildcards '*/drivers/hwmon/nzxt-smart2.c'
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
