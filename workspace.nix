# The Nix side of the pnpm workspace in this directory.
{
  lib,
  fetchPnpmDeps,
  pnpm_11,
}:
let
  manifests = lib.fileset.unions [
    ./package.json
    ./pnpm-lock.yaml
    ./pnpm-workspace.yaml
    (lib.fileset.fileFilter (file: file.name == "package.json") ./pkgs)
  ];
in
{
  inherit manifests;
  pnpm = pnpm_11;

  # Only the manifests, so editing code does not refetch the dependencies.
  pnpmDeps = fetchPnpmDeps {
    pname = "carbos";
    version = "0";
    pnpm = pnpm_11;
    src = lib.fileset.toSource {
      root = ./.;
      fileset = manifests;
    };
    fetcherVersion = 4;
    hash = "sha256-2s1y9ddE+NvxCxv5HcRS1M7G/3TMafmg6SKzwPMsPNs=";
  };
}
