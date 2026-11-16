{ callPackage, unstable }:
let
  # Vesktop comes from unstable, so Vencord has to keep up with it.
  nixpkgs = unstable.vencord;

  workspace = callPackage ./workspace.nix { inherit types; };
  types = callPackage ./types.nix { vencord = nixpkgs; };
  catalog = callPackage ./catalog.nix {
    vencord = nixpkgs;
    inherit workspace;
  };
in
nixpkgs.overrideAttrs (old: {
  # esbuild applies the tsconfig nearest to a file's real path. Ours maps the
  # Vencord imports to declarations, so the plugins are copied, not linked.
  preBuild = (old.preBuild or "") + ''
    mkdir -p src/userplugins
    for plugin in ${workspace}/pkgs/vencord/plugins/*; do
      target="src/userplugins/$(basename "$plugin")"
      cp -r --no-preserve=mode "$plugin" "$target"
      if [ -e "$plugin/node_modules" ]; then
        rm -rf "$target/node_modules"
        ln -s "$plugin/node_modules" "$target/node_modules"
      fi
    done
  '';

  passthru = old.passthru // {
    inherit catalog types workspace;
  };
})
