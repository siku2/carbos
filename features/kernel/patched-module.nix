{
  lib,
  stdenv,
  kernel,
  kernelModuleMakeFlags,
  # Directory of the modules' Makefile, relative to the source root.
  dir,
  modules,
  patches,
  # Source directories to unpack. Must cover everything the Makefile reaches.
  unpack ? [ dir ],
}:
stdenv.mkDerivation {
  pname = "${lib.concatStringsSep "-" modules}-patched";
  inherit (kernel) version src;
  inherit patches;

  unpackPhase = ''
    mkdir source
    cd source
    tar -xf $src --strip-components=1 --wildcards ${
      lib.concatMapStringsSep " " (path: lib.escapeShellArg "*/${path}/*") unpack
    }

    # Trace headers name their path relative to the kernel's include/trace.
    mkdir -p include/trace
  '';

  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernelModuleMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "M=$(PWD)/${dir}"
    "INSTALL_MOD_PATH=$(out)"
    "INSTALL_MOD_DIR=updates"
  ];

  preBuild = ''
    makeFlagsArray+=("KCFLAGS=-I$PWD/include/trace")
  '';

  enableParallelBuilding = true;
  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];

  # The Makefile builds every module it lists. Keep only the patched ones.
  postInstall = ''
    find $out -name '*.ko*' ${
      lib.concatMapStringsSep " " (module: "! -name ${lib.escapeShellArg "${module}.ko*"}") modules
    } -delete
  '';
}
