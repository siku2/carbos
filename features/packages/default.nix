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

  # Some nixpkgs packages claim darwin support but depend on Linux-only ones.
  isBuildable = package: lib.isDerivation package && (builtins.tryEval package.drvPath).success;
  buildable = lib.filterAttrs (_: isBuildable);

  # Update scripts get their file as an argument. Lists are commands in the
  # nixpkgs style, like nix-update-script.
  update =
    path: package:
    let
      file = "pkgs/${lib.concatStringsSep "/" path}/default.nix";
      script = package.updateScript;
      command =
        if lib.isList script then
          lib.escapeShellArgs (map toString script)
        else
          "${lib.getExe script} ${file}";
      # Overrides inherit the update scripts of nixpkgs, which only work there.
      position = builtins.unsafeGetAttrPos "updateScript" (package.passthru or { });
      own = position != null && lib.hasPrefix (toString ../../pkgs) position.file;
    in
    lib.optional own "UPDATE_NIX_ATTR_PATH=${lib.concatStringsSep "." path} ${command}";

  # A directory that is a set of packages, like pkgs/device-firmware, has one level
  # of members.
  updates =
    all:
    lib.concatMap (
      name:
      let
        value = all.${name};
      in
      if isBuildable value then
        update [ name ] value
      else if lib.isAttrs value && !lib.isDerivation value then
        lib.concatLists (
          lib.mapAttrsToList (
            member:
            update [
              name
              member
            ]
          ) (buildable value)
        )
      else
        [ ]
    ) names;
in
{
  imports = [ ./unstable.nix ];

  flake.overlays.default = composed;

  perSystem =
    { pkgs, ... }:
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
      packages = buildable (lib.getAttrs names all);

      apps.update = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "update";
            runtimeInputs = [ pkgs.git ];
            text = ''
              cd "$(git rev-parse --show-toplevel)"
              nix flake update
              ${lib.concatLines (updates all)}
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
