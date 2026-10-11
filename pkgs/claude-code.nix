{
  claude-code,
  lib,
  stdenv,
}:
let
  inherit (claude-code) installPhase;
  libraryPath = builtins.match ".*--prefix LD_LIBRARY_PATH : ([^ ]+) .*" installPhase;
in
# nixpkgs finds the voice module's libasound through LD_LIBRARY_PATH, which
# every command started from Claude Code inherits. An RPATH, unlike a RUNPATH,
# also applies to the module, so record the path there instead.
if !stdenv.hostPlatform.isLinux then
  claude-code
else
  assert lib.assertMsg (
    libraryPath != null
  ) "claude-code no longer sets LD_LIBRARY_PATH, drop pkgs/claude-code.nix.";
  claude-code.overrideAttrs {
    installPhase =
      builtins.replaceStrings [ "--prefix LD_LIBRARY_PATH : ${lib.head libraryPath} " ] [ "" ]
        installPhase;
    runtimeDependencies = [ (lib.removeSuffix "/lib" (lib.head libraryPath)) ];
    patchelfFlags = [ "--force-rpath" ];
  }
