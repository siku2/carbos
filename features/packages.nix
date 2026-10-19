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

  # Update scripts get their file as an argument. Lists are commands in the
  # nixpkgs style, like nix-update-script.
  updates =
    packages:
    lib.concatLists (
      lib.mapAttrsToList (
        entry: type:
        let
          name = lib.removeSuffix ".nix" entry;
          file = if type == "directory" then "pkgs/${entry}/default.nix" else "pkgs/${entry}";
          script = packages.${name}.updateScript;
          command =
            if lib.isList script then
              lib.escapeShellArgs (map toString script)
            else
              "${lib.getExe script} ${file}";
          # Overrides inherit the update scripts of nixpkgs, which only work there.
          position = builtins.unsafeGetAttrPos "updateScript" (packages.${name}.passthru or { });
          own = position != null && lib.hasPrefix (toString ../pkgs) position.file;
        in
        lib.optional own "UPDATE_NIX_ATTR_PATH=${name} ${command}"
      ) (builtins.readDir ../pkgs)
    );
in
{
  flake.overlays.default = composed;

  perSystem =
    { config, pkgs, ... }:
    let
      all = import pkgs.path {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.allowUnfree = true;
        overlays = [
          inputs.self.overlays.unstable
          localPackages
        ];
      };
    in
    {
      # Some nixpkgs packages claim darwin support but depend on Linux-only ones.
      packages = lib.filterAttrs (
        _: package: lib.isDerivation package && (builtins.tryEval package.drvPath).success
      ) (lib.getAttrs (map (lib.removeSuffix ".nix") (lib.attrNames (builtins.readDir ../pkgs))) all);

      apps.update = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "update";
            runtimeInputs = [ pkgs.git ];
            text = ''
              cd "$(git rev-parse --show-toplevel)"
              nix flake update
              ${lib.concatLines (updates config.packages)}
            '';
          }
        );
      };
    };

  flake.modules = {
    nixos.packages = packages;
    darwin.packages = packages;
  };
}
