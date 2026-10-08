{ rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "cargo-clean-all";
  version = "0.6.5";

  src = fetchFromGitHub {
    owner = "dnlmlr";
    repo = "cargo-clean-all";
    rev = "v${version}";
    hash = "sha256-CJzjw/g0Ap7TKC2m+bVlH+/iCUOQITmE6HGvrNzWQ3o=";
  };
  cargoHash = "sha256-9Qv2/XacE82AtZCZS5vtSeVdnD6Ugs+Qn/EVevMndQM=";
}
