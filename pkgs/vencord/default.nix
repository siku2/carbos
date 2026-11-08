{ callPackage, path }:
let
  # Inside the overlay, `vencord` already refers to this package.
  nixpkgs = callPackage (path + "/pkgs/by-name/ve/vencord/package.nix") { };

  # TODO: drop once nixpkgs ships 1.15.16, which fixes Discord's rspack update.
  upstream = nixpkgs.overrideAttrs (old: {
    version = "1.15.16";
    src = old.src.override { hash = "sha256-aUJubLJpyLAZWiOezqFxPY6oVPgWVPQpajFqrJvrO9U="; };
    patches = [ ];
    postPatch = "";
    pnpmDeps = old.pnpmDeps.overrideAttrs {
      outputHash = "sha256-1HcQH0ZZixQvziehIDhyBUB8v5ckufxrS2yUq2BcMVQ=";
    };
  });

  workspace = callPackage ./workspace.nix { inherit types; };
  types = callPackage ./types.nix { vencord = upstream; };
  catalog = callPackage ./catalog.nix {
    vencord = upstream;
    inherit workspace;
  };
in
upstream.overrideAttrs (old: {
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
