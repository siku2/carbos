{
  fetchFromGitHub,
  nix-update-script,
  rustPlatform,
}:

rustPlatform.buildRustPackage rec {
  pname = "cargo-clean-all";
  version = "0.6.6";

  src = fetchFromGitHub {
    owner = "dnlmlr";
    repo = "cargo-clean-all";
    rev = "v${version}";
    hash = "sha256-RPDxeoUoAXNFh2ZabHigmwlztyRG9l9zez1UulrtNyo=";
  };
  cargoHash = "sha256-s/xOS86ncB3gxGiZIXantF/ID/LhpMEkmtD0r8E1/bA=";

  passthru.updateScript = nix-update-script { extraArgs = [ "--flake" ]; };
}
