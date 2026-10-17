{ inputs, lib, ... }:
let
  dir = ../features;

  isFeature =
    name: type:
    !lib.hasPrefix "_" name
    && (
      (type == "regular" && lib.hasSuffix ".nix" name)
      || (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"))
    );

  files = lib.attrNames (lib.filterAttrs isFeature (builtins.readDir dir));
in
{
  imports = [ inputs.flake-parts.flakeModules.modules ] ++ map (name: dir + "/${name}") files;
}
