{ pkgs }:
let
  nightly = pkgs.rust-bin.selectLatestNightlyWith (
    toolchain:
    toolchain.default.override {
      extensions = [
        "rust-analyzer"
        "rust-src"
      ];
    }
  );
in
{
  packages = [
    pkgs.rustup
    pkgs.cargo-nextest
    pkgs.cmake
    pkgs.pkg-config
  ];

  shellHook = ''
    _rust_preset_pinned() {
      local dir=$PWD
      while [ -n "$dir" ]; do
        if [ -e "$dir/rust-toolchain.toml" ] || [ -e "$dir/rust-toolchain" ]; then
          return 0
        fi
        dir=''${dir%/*}
      done
      return 1
    }

    if ! _rust_preset_pinned; then
      export PATH="${nightly}/bin:$PATH"
    fi

    unset -f _rust_preset_pinned
  '';

  env = {
    LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
    BINDGEN_EXTRA_CLANG_ARGS = "-isystem ${pkgs.llvmPackages.libclang.lib}/lib/clang/${pkgs.lib.versions.major pkgs.llvmPackages.libclang.version}/include -isysroot ${pkgs.apple-sdk.sdkroot}";
  };
}
