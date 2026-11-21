{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "sxlink";
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
    description = "Attach USB devices from Silex USB device servers through vhci_hcd";
    mainProgram = "sxlink";
    platforms = lib.platforms.linux;
  };
}
