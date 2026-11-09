{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "razer-kbd-flash";
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
    description = "Update the firmware of a Razer BlackWidow Chroma V2";
    mainProgram = "razer-kbd-flash";
    platforms = lib.platforms.linux;
  };
}
