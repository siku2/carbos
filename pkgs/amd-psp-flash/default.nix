{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "amd-psp-flash";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./clippy.toml
      ./src
    ];
  };
  cargoLock.lockFile = ./Cargo.lock;

  meta = {
    description = "Update a Navi3x VBIOS through the PSP bootloader";
    mainProgram = "amd-psp-flash";
    platforms = lib.platforms.linux;
  };
}
