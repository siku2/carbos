{ lib, ... }:
let
  # A file that takes its own name as an argument gets the nixpkgs version.
  local =
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
  overlay =
    final: prev:
    lib.mapAttrs (
      name: package:
      if lib.meta.availableOn prev.stdenv.hostPlatform package then package else prev.${name} or package
    ) (local final prev);

  packages.nixpkgs.overlays = [ overlay ];
in
{
  flake.overlays.default = overlay;

  flake.modules = {
    nixos.packages = packages;
    darwin.packages = packages;
  };
}
