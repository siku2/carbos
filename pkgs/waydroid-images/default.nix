{
  lib,
  curl,
  fetchurl,
  gnused,
  jq,
  runCommand,
  unzip,
  writeShellApplication,
}:
let
  image =
    {
      kind,
      path,
      file,
      hash,
    }:
    fetchurl {
      url = "mirror://sourceforge/waydroid/images/${kind}/${path}/${file}";
      inherit hash;
    };

  system = image {
    kind = "system";
    path = "lineage/waydroid_x86_64";
    file = "lineage-20.0-20260927-VANILLA-waydroid_x86_64-system.zip";
    hash = "sha256-BTVSclv0riXi0/fm8ZRyAylKqdc9wX/h86vmRuXTvYo=";
  };

  vendor = image {
    kind = "vendor";
    path = "waydroid_x86_64";
    file = "lineage-20.0-20261022-MAINLINE-waydroid_x86_64-vendor.zip";
    hash = "sha256-kWY8M3ATFFIItsUz1+H6KpFamGTdyPxWlm9AzXWWSKw=";
  };
in
runCommand "waydroid-images"
  {
    nativeBuildInputs = [ unzip ];

    passthru.updateScript = writeShellApplication {
      name = "waydroid-images-update";
      runtimeInputs = [
        curl
        gnused
        jq
      ];
      text = builtins.readFile ./update.sh;
    };

    meta = {
      description = "LineageOS system and vendor images for Waydroid";
      platforms = [ "x86_64-linux" ];
      license = lib.licenses.asl20;
    };
  }
  ''
    mkdir $out
    unzip -d $out ${system} system.img
    unzip -d $out ${vendor} vendor.img
  ''
