{
  lib,
  stdenvNoCC,
  fetchPnpmDeps,
  nodejs,
  pnpm_11,
  pnpmConfigHook,
  systemdMinimal,
  types,
}:
let
  pnpm = pnpm_11;

  manifests = lib.fileset.unions [
    ./package.json
    ./pnpm-lock.yaml
    ./pnpm-workspace.yaml
    (lib.fileset.fileFilter (file: file.name == "package.json") ./packages)
    (lib.fileset.fileFilter (file: file.name == "package.json") ./plugins)
  ];
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "vencord-plugins";
  version = "0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      manifests
      ./tsconfig.json
      ./packages
      ./plugins
    ];
  };

  # Only the manifests, so editing a plugin does not refetch the dependencies.
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version;
    inherit pnpm;
    src = lib.fileset.toSource {
      root = ./.;
      fileset = manifests;
    };
    fetcherVersion = 4;
    hash = "sha256-VL1fpPIN1NUooRlE6np8yLH8dF7Egllrq77zdnAEEZg=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
    # varlinkctl, the reference client for the varlink tests.
    systemdMinimal
  ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    pnpm run generate --check
    ln -s ${types} .vencord-types
    pnpm run typecheck
    rm .vencord-types
    pnpm run test

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    cp -r . $out

    runHook postInstall
  '';
})
