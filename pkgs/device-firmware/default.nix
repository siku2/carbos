{ lib, callPackage }:
let
  dirs = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./.));
in
lib.genAttrs dirs (name: callPackage ./${name} { })
