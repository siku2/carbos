# The installer as a directory that boots by kexec from anywhere: kernel,
# initrd, command line, a static kexec and the script that loads them. On a
# machine without nix, copy the directory over and run bin/carbos-kexec.
{
  lib,
  runCommand,
  pkgsStatic,
  installer,
}:
let
  inherit (installer.config) boot system;
in
runCommand "carbos-kexec"
  {
    meta.mainProgram = "carbos-kexec";
    cmdline = builtins.unsafeDiscardStringContext "init=${system.build.toplevel}/init ${toString boot.kernelParams}";
    passAsFile = [ "cmdline" ];
  }
  ''
    mkdir -p $out/bin
    cp ${system.build.kernel}/${system.boot.loader.kernelFile} $out/kernel
    cp ${system.build.netbootRamdisk}/initrd $out/initrd
    cp $cmdlinePath $out/cmdline
    cp ${lib.getExe' pkgsStatic.kexec-tools "kexec"} $out/bin/kexec
    install -m 755 ${./carbos-kexec.sh} $out/bin/carbos-kexec
  ''
