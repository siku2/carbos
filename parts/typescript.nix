{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      workspace = pkgs.callPackage ../workspace.nix { };
    in
    {
      # Scripts outside the projects with their own check.
      checks.typescript = pkgs.stdenvNoCC.mkDerivation {
        name = "typescript";

        src = lib.fileset.toSource {
          root = ../.;
          fileset = lib.fileset.unions [
            workspace.manifests
            ../tsconfig.base.json
            ../tsconfig.json
            (lib.fileset.difference (lib.fileset.fileFilter (file: file.hasExt "ts") ../.) ../pkgs/vencord)
          ];
        };

        inherit (workspace) pnpmDeps;

        nativeBuildInputs = [
          pkgs.nodejs
          workspace.pnpm
          pkgs.pnpmConfigHook
        ];

        buildPhase = ''
          runHook preBuild
          pnpm exec tsc
          runHook postBuild
        '';

        installPhase = "touch $out";
      };
    };
}
