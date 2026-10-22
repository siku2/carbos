{
  config,
  inputs,
  lib,
  ...
}:
let
  dir = ../features;

  entries = builtins.readDir dir;
  features = lib.attrNames (lib.filterAttrs (_: type: type == "directory") entries);
  stray = lib.attrNames (lib.filterAttrs (_: type: type != "directory") entries);

  # Hosts only import system modules. A feature's home half comes along.
  withHome = lib.mapAttrs (_: home: { home-manager.sharedModules = [ home ]; }) (
    config.flake.modules.homeManager or { }
  );
in
{
  imports = [
    inputs.flake-parts.flakeModules.modules
  ]
  ++
    lib.throwIf (stray != [ ])
      "features/ only holds directories, move ${lib.concatStringsSep ", " stray} into one"
      (map (name: dir + "/${name}") features);

  flake.modules = {
    nixos = withHome;
    darwin = withHome;
  };
}
