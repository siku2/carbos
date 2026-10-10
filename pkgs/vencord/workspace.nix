{
  callPackage,
  lib,
  nodejs,
  pnpmConfigHook,
  stdenvNoCC,
  systemdMinimal,
  types,
}:
let
  workspace = callPackage ../../workspace.nix { };
in
stdenvNoCC.mkDerivation {
  pname = "vencord-plugins";
  version = "0";

  # The whole pnpm workspace has to be there for the install.
  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      workspace.manifests
      ../../tsconfig.base.json
      ./tsconfig.json
      ./packages
      ./plugins
    ];
  };

  inherit (workspace) pnpmDeps;

  nativeBuildInputs = [
    nodejs
    workspace.pnpm
    pnpmConfigHook
    # varlinkctl, the reference client for the varlink tests.
    systemdMinimal
  ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    pushd pkgs/vencord
    pnpm run generate --check
    ln -s ${types} .vencord-types
    pnpm run typecheck
    rm .vencord-types
    pnpm run test
    popd

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    cp -r . $out

    runHook postInstall
  '';
}
