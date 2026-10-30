{
  jq,
  vencord,
  workspace,
}:
# Names of the plugins Vencord ships and of ours in userplugins.
vencord.overrideAttrs (old: {
  pname = "vencord-plugins.json";
  inherit (vencord) pnpmDeps;

  nativeBuildInputs = old.nativeBuildInputs ++ [ jq ];

  buildPhase = ''
    runHook preBuild

    pnpm run generatePluginJson upstream.json readmes.json
    for index in ${workspace}/pkgs/vencord/plugins/*/index.ts; do
      dir=$(basename "$(dirname "$index")")
      name="''${dir^}"
      if ! grep -q "name: \"$name\"" "$index"; then
        echo "$index does not define a plugin named $name" >&2
        exit 1
      fi
      echo "$name"
    done >userplugins

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    jq --rawfile ours userplugins \
      '[.[] | {name, required, enabledByDefault}]
        + [$ours | split("\n")[] | select(. != "")
          | {name: ., required: false, enabledByDefault: false}]' \
      upstream.json >$out

    runHook postInstall
  '';
})
