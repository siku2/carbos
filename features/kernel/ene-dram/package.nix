{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
}:
stdenv.mkDerivation {
  pname = "ene-dram";
  inherit (kernel) version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Kbuild
      ./ene_dram.c
    ];
  };

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
