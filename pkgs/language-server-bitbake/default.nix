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
  pname = "language-server-bitbake";
  version = "2.10.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/language-server-bitbake/-/language-server-bitbake-${finalAttrs.version}.tgz";
    hash = "sha256-Qg3WzG/6OoH7ayIdLQ5/DnB92rKPKfsHJhqH7XL2rwo=";
  };

  # The registry tarball ships prebuilt JavaScript but no lockfile. Its
  # workspaces entry points outside the package and breaks npm.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    ${lib.getExe' nodejs "npm"} pkg delete workspaces scripts devDependencies
  '';

  npmDepsHash = "sha256-+S9Vm67p8lFoSQILO0jlc7xEPpZEHVWA2+Ule/N7104=";
  dontNpmBuild = true;

  passthru.updateScript = writeShellApplication {
    name = "language-server-bitbake-update";
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
    description = "BitBake language server from the Yocto Project";
    homepage = "https://github.com/yoctoproject/vscode-bitbake";
    license = lib.licenses.mit;
    mainProgram = "language-server-bitbake";
  };
})
