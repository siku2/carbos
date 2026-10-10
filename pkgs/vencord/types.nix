{ vencord }:
# Vencord's own release flow for @vencord/types, built from the source we ship.
vencord.overrideAttrs {
  pname = "vencord-types";

  buildPhase = ''
    runHook preBuild

    pnpm run generateTypes
    pnpm --dir packages/vencord-types exec tsx prepare.ts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    pnpm --config.inject-workspace-packages=true --filter @vencord/types deploy --prod --offline $out
    rm $out/pnpm-lock.yaml $out/pnpm-workspace.yaml

    runHook postInstall
  '';
}
