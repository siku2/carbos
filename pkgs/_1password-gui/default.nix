{
  lib,
  stdenv,
  _1password-gui,
  curl,
  fetchurl,
  gawk,
  jq,
  writeShellApplication,
  # The NixOS module overrides this.
  polkitPolicyOwners ? [ ],
}:

# nixpkgs lags behind the releases.
let
  sources = lib.importJSON ./sources.json;
  os = stdenv.hostPlatform.parsed.kernel.name;
  arch = stdenv.hostPlatform.parsed.cpu.name;
  inherit (sources.${os}) version;

  urls = {
    darwin = "https://downloads.1password.com/mac/1Password-${version}-${arch}.zip";
    linux =
      let
        alias =
          {
            x86_64 = "x64";
            aarch64 = "arm64";
          }
          .${arch};
      in
      "https://downloads.1password.com/linux/tar/stable/${arch}/1password-${version}.${alias}.tar.gz";
  };
in
(_1password-gui.override { inherit polkitPolicyOwners; }).overrideAttrs (old: {
  inherit version;

  src = fetchurl {
    url = urls.${os};
    hash = sources.${os}.hashes.${arch};
  };

  passthru = (old.passthru or { }) // {
    updateScript = writeShellApplication {
      name = "1password-gui-update";
      runtimeInputs = [
        curl
        gawk
        jq
      ];
      text = builtins.readFile ./update.sh;
    };
  };
})
