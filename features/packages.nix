{ inputs, lib, ... }:
let
  # A file that takes its own name as an argument gets the package it replaces.
  localPackages =
    final: prev:
    lib.mapAttrs' (
      file: _:
      let
        name = lib.removeSuffix ".nix" file;
        path = ../pkgs + "/${file}";
        namesake = lib.optionalAttrs (prev ? ${name}) { ${name} = prev.${name}; };
      in
      lib.nameValuePair name (
        final.callPackage path (lib.intersectAttrs (lib.functionArgs (import path)) namesake)
      )
    ) (builtins.readDir ../pkgs);

  # A local package only replaces its nixpkgs namesake on the platforms it
  # declares, so the darwin app bundles never shadow nixpkgs on Linux.
  local =
    final: prev:
    lib.mapAttrs (
      name: package:
      if lib.meta.availableOn prev.stdenv.hostPlatform package then package else prev.${name} or package
    ) (localPackages final prev);

  # The local packages see the unstable pins as their namesakes.
  composed = lib.composeManyExtensions [
    inputs.self.overlays.unstable
    local
  ];

  packages.nixpkgs.overlays = [ composed ];
in
{
  flake.overlays.default = composed;

  flake.modules = {
    nixos.packages = packages;
    darwin.packages = packages;
  };
}
