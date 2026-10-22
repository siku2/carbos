{ inputs, lib, ... }:
let
  entries = builtins.readDir ../../pkgs;
  stray = lib.attrNames (lib.filterAttrs (_: type: type != "directory") entries);
  names =
    lib.throwIf (stray != [ ])
      "pkgs/ only holds directories, move ${lib.concatStringsSep ", " stray} into one"
      (lib.attrNames entries);

  # A package that takes its own name as an argument gets the one it replaces.
  localPackages =
    final: prev:
    lib.genAttrs names (
      name:
      let
        path = ../../pkgs/${name};
        namesake = lib.optionalAttrs (prev ? ${name}) { ${name} = prev.${name}; };
      in
      final.callPackage path (lib.intersectAttrs (lib.functionArgs (import path)) namesake)
    );

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
    lib.concatMap (
      name:
      let
        file = "pkgs/${name}/default.nix";
        script = packages.${name}.updateScript;
        command =
          if lib.isList script then
            lib.escapeShellArgs (map toString script)
          else
            "${lib.getExe script} ${file}";
        # Overrides inherit the update scripts of nixpkgs, which only work there.
        position = builtins.unsafeGetAttrPos "updateScript" (packages.${name}.passthru or { });
        own = position != null && lib.hasPrefix (toString ../../pkgs) position.file;
      in
      lib.optional own "UPDATE_NIX_ATTR_PATH=${name} ${command}"
    ) names;
in
{
  imports = [ ./unstable.nix ];

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
      ) (lib.getAttrs names all);

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
