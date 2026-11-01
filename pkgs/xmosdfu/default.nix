{
  lib,
  stdenv,
  fetchFromGitHub,
  libusb1,
  pkg-config,
}:

# The DFU host tool from lib_xua 4.x. lib_dfu 2.x replaced it with one that
# uses plain DFU_DETACH, which older XMOS firmware like the SSL 2 MkII does
# not answer.
stdenv.mkDerivation rec {
  pname = "xmosdfu";
  version = "4.2.0";

  src = fetchFromGitHub {
    owner = "xmos";
    repo = "lib_xua";
    rev = "v${version}";
    hash = "sha256-578vXcYdLyGj7IMZkMaWA+89YSN4x3z8EZjWdVl2eL4=";
  };

  sourceRoot = "${src.name}/lib_xua/host/xmosdfu";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libusb1 ];

  # Devices from other vendors set XMOSDFU_VID.
  postPatch = ''
    substituteInPlace xmosdfu.cpp \
      --replace-fail '#define XMOS_VID 0x20b1' \
        'static unsigned int xmos_vid(void) { const char *v = getenv("XMOSDFU_VID"); return v ? (unsigned int)strtoul(v, NULL, 16) : 0x20b1; }' \
      --replace-fail 'desc.idVendor == XMOS_VID' 'desc.idVendor == xmos_vid()'
  '';

  buildPhase = ''
    runHook preBuild
    $CXX -O2 -Wall -o xmosdfu xmosdfu.cpp $(pkg-config --cflags --libs libusb-1.0)
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 xmosdfu $out/bin/xmosdfu
    runHook postInstall
  '';

  meta = {
    description = "XMOS USB audio DFU host tool";
    homepage = "https://github.com/xmos/lib_xua";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
    mainProgram = "xmosdfu";
  };
}
