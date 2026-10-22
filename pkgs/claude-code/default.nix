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
# every command started from Claude Code inherits. Drop it at the cost of voice
# input. Adding an RPATH instead makes patchelf overlap the LOAD segments of
# the Bun binary, which then crashes in ld.so.
if !stdenv.hostPlatform.isLinux then
  claude-code
else
  assert lib.assertMsg (
    libraryPath != null
  ) "claude-code no longer sets LD_LIBRARY_PATH, drop pkgs/claude-code.";
  claude-code.overrideAttrs {
    installPhase =
      builtins.replaceStrings [ "--prefix LD_LIBRARY_PATH : ${lib.head libraryPath} " ] [ "" ]
        installPhase;
  }
