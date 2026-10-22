{
  config,
  inputs,
  lib,
  ...
}:
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

  # Hosts only import system modules. A feature's home half comes along.
  withHome = lib.mapAttrs (_: home: { home-manager.sharedModules = [ home ]; }) (
    config.flake.modules.homeManager or { }
  );
in
{
  imports = [ inputs.flake-parts.flakeModules.modules ] ++ map (name: dir + "/${name}") files;

  flake.modules = {
    nixos = withHome;
    darwin = withHome;
  };
}
