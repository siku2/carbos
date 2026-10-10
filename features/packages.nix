{ lib, ... }:
let
  local =
    final:
    lib.mapAttrs' (
      file: _:
      lib.nameValuePair (lib.removeSuffix ".nix" file) (final.callPackage (../pkgs + "/${file}") { })
    ) (builtins.readDir ../pkgs);

  # A local package only replaces its nixpkgs namesake on the platforms it
  # declares, so the darwin app bundles never shadow nixpkgs on Linux.
  overlay =
    final: prev:
    lib.mapAttrs (
      name: package:
      if lib.meta.availableOn prev.stdenv.hostPlatform package then package else prev.${name} or package
    ) (local final);

  packages.nixpkgs.overlays = [ overlay ];
in
{
  flake.overlays.default = overlay;

  flake.modules = {
    nixos.packages = packages;
    darwin.packages = packages;
  };
}
