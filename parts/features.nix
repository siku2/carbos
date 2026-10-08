{ inputs, lib, ... }:
let
  dir = ../features;

  isFeature = name: type: type == "regular" && lib.hasSuffix ".nix" name && !lib.hasPrefix "_" name;

  files = lib.attrNames (lib.filterAttrs isFeature (builtins.readDir dir));
in
{
  imports = [ inputs.flake-parts.flakeModules.modules ] ++ map (name: dir + "/${name}") files;
}
