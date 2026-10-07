{
  lib,
  writeShellApplication,
  writeText,
  coreutils,
  curl,
  findutils,
  gawk,
  git,
  gptfdisk,
  gum,
  jq,
  nix-output-monitor,
  nixos-install-tools,
  parted,
  util-linux,
  bundle,
}:
writeShellApplication {
  name = "carbos-install";
  runtimeInputs = [
    coreutils
    curl
    findutils
    gawk
    git
    gptfdisk
    gum
    jq
    nix-output-monitor
    nixos-install-tools
    parted
    util-linux
  ];
  runtimeEnv.CARBOS_BUNDLE = writeText "carbos-bundle.json" (builtins.toJSON bundle);
  # main.sh runs the installer, so it has to come last.
  text = lib.concatMapStrings builtins.readFile [
    ./src/ui.sh
    ./src/bundle.sh
    ./src/disk.sh
    ./src/steps.sh
    ./src/main.sh
  ];
}
