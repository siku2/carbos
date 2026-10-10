{ callPackage, path }:
let
  # Inside the overlay, `vencord` already refers to this package.
  upstream = callPackage (path + "/pkgs/by-name/ve/vencord/package.nix") { };

  workspace = callPackage ./workspace.nix { inherit types; };
  types = callPackage ./types.nix { vencord = upstream; };
in
upstream.overrideAttrs (old: {
  # esbuild applies the tsconfig nearest to a file's real path. Ours maps the
  # Vencord imports to declarations, so the plugins are copied, not linked.
  preBuild = (old.preBuild or "") + ''
    mkdir -p src/userplugins
    for plugin in ${workspace}/plugins/*; do
      target="src/userplugins/$(basename "$plugin")"
      cp -r --no-preserve=mode "$plugin" "$target"
      if [ -e "$plugin/node_modules" ]; then
        rm -rf "$target/node_modules"
        ln -s "$plugin/node_modules" "$target/node_modules"
      fi
    done
  '';

  passthru = old.passthru // {
    inherit types workspace;
  };
})
