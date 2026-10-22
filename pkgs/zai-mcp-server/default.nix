{
  lib,
  buildNpmPackage,
  curl,
  fetchurl,
  gnused,
  gnutar,
  gzip,
  jq,
  nodejs,
  prefetch-npm-deps,
  writeShellApplication,
}:

buildNpmPackage (finalAttrs: {
  pname = "zai-mcp-server";
  version = "0.1.5";

  src = fetchurl {
    url = "https://registry.npmjs.org/@z_ai/mcp-server/-/mcp-server-${finalAttrs.version}.tgz";
    hash = "sha256-faQQkRDjn1tSHy5asI8jtToi8gGfBwMT+gEfCW6e1BU=";
  };

  # The registry tarball ships prebuilt JavaScript but no lockfile.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    ${lib.getExe' nodejs "npm"} pkg delete scripts.prepare
  '';

  npmDepsHash = "sha256-rtuyCucm1efHhsgPYHdl55mHWJfwqmaUcHqNQjMHzXo=";
  dontNpmBuild = true;

  passthru.updateScript = writeShellApplication {
    name = "zai-mcp-server-update";
    runtimeInputs = [
      curl
      gnused
      gnutar
      gzip
      jq
      nodejs
      prefetch-npm-deps
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "Z.ai vision MCP server";
    homepage = "https://docs.z.ai/devpack/mcp/vision-mcp-server";
    license = lib.licenses.asl20;
    mainProgram = "zai-mcp-server";
  };
})
