{
  lib,
  clangStdenv,
  fetchFromGitHub,
  fetchurl,
  git,
  cmake,
  ninja,
  llvmPackages,
  pkg-config,
  glslang,
  python3,
  qt6,
  copyDesktopItems,
  makeDesktopItem,
  makeShellWrapper,
  alsa-lib,
  dbus,
  ffmpeg-headless,
  libdecor,
  libglvnd,
  libpulseaudio,
  libx11,
  libxcursor,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxscrnsaver,
  libxtst,
  systemd,
  vulkan-loader,
  wayland,
  wayland-protocols,
  writeShellApplication,
  curl,
  gnused,
  jq,
  nix-prefetch-github,
}:

let
  # SDL and the Vulkan loader are opened with dlopen at runtime.
  runtimeLibraries = [
    alsa-lib
    dbus
    libdecor
    libglvnd
    libpulseaudio
    libx11
    libxcursor
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxscrnsaver
    libxtst
    systemd
    vulkan-loader
    wayland
  ];

  # Pinned in 3rdparty/CMakeLists.txt, which fetches them at configure time.
  fetchContent = {
    opus = fetchFromGitHub {
      owner = "xiph";
      repo = "opus";
      rev = "ddbe48383984d56acd9e1ab6a090c54ca6b735a6";
      hash = "sha256-M1G7ypcfs7nJmXgkyoG96jT/CkgN5BOzy+DGO4LVCvA=";
    };
    openxr = fetchFromGitHub {
      owner = "KhronosGroup";
      repo = "OpenXR-SDK";
      rev = "f2448a8797c85814aa892efc1ab8707900fbcc78";
      hash = "sha256-glcHMArDabXbrxO4CY2QeTJFTeUTQH4v1O03LuhML7E=";
    };
    xbyak = fetchFromGitHub {
      owner = "herumi";
      repo = "xbyak";
      rev = "44a72f369268f7d552650891b296693e91db86bb";
      hash = "sha256-S4arAwbhTGsUhDFfy5fTGyDvCm0/x/LKiiPTAuRM8Yk=";
    };
    zydis = fetchFromGitHub {
      owner = "zyantific";
      repo = "zydis";
      rev = "120e0e705f8e3b507dc49377ac2879979f0d545c";
      fetchSubmodules = true;
      hash = "sha256-bjQCaYRA94CGBsxG+UOuDDyLrH3k2ERJbn0+7ITGLeU=";
    };
    zstd = fetchFromGitHub {
      owner = "facebook";
      repo = "zstd";
      rev = "f8745da6ff1ad1e7bab384bd1f9d742439278e99";
      hash = "sha256-tNFWIT9ydfozB8dWcmTMuZLCQmQudTFJIkSr0aG7S44=";
    };
  };

  # Upstream patches this one, so it gets a writable copy. The patch has
  # CRLF line endings that only git apply handles.
  zarchive = fetchFromGitHub {
    owner = "Exzap";
    repo = "ZArchive";
    rev = "d2c717730092c7bf8cbb033b12fd4001b7c4d932";
    hash = "sha256-hX637O/mVLTzmG0a9swJu9w+3o26VHo+K/9RhMuf1lI=";
  };

  # file(DOWNLOAD) skips a file that is already there with the expected hash.
  notoSans =
    lib.concatMapAttrsStringSep "\n"
      (
        path: sha256:
        let
          file = fetchurl {
            url = "https://raw.githubusercontent.com/notofonts/notofonts.github.io/42af67ccd12bc0e31ed85384bf73e39248265374/fonts/${path}";
            inherit sha256;
          };
        in
        "install -Dm644 ${file} build/_deps/noto-sans/${baseNameOf path}"
      )
      {
        LICENSE = "f2095b08bed08b23a6fe26112fcd679a2bee3f002eef077eb05d215ed1051bd8";
        "NotoSans/hinted/ttf/NotoSans-Regular.ttf" =
          "478c558ea716033cd60c03438f628dfa75694dcf6b5f6d505a2f05fd2b4f3823";
        "NotoSans/hinted/ttf/NotoSans-Bold.ttf" =
          "1df075a380fc7cb898acf64c1f7b3b4dd780de3caa860178bf929de35817a913";
        "NotoSans/hinted/ttf/NotoSans-Italic.ttf" =
          "467e3f89eeca4108bb8710a2b9e0cf2281ac56d5b0609211a83776d0505eecb5";
        "NotoSans/hinted/ttf/NotoSans-BoldItalic.ttf" =
          "1b602a9d6353be42c91df097a4857b69fa2696f26703d7a33b54a15d87c2622c";
      };
in
clangStdenv.mkDerivation (finalAttrs: {
  pname = "kytyps5";
  version = "0.3.0-unstable-2026-11-24";

  src = fetchFromGitHub {
    owner = "KytyPS5";
    repo = "KytyPS5";
    rev = "b446af9d26e000b5dd93ecfc8bf5403ad500e9fd";
    fetchSubmodules = true;
    hash = "sha256-Pkpc2bKeC2wDgFfaGPKCAgr9O0nPfH9G2jAP/ATY2Zc=";
  };

  patches = [
    ./build-stamp.patch
    ./working-directory.patch
    ./system-ffmpeg.patch
  ];

  # The source has no .git, so the version script falls back to these.
  postPatch = ''
    substituteInPlace src/generate_version.cmake \
      --replace-fail 'set(KYTY_GIT_VERSION "unknown")' 'set(KYTY_GIT_VERSION "${finalAttrs.version}")' \
      --replace-fail 'set(KYTY_GIT_HASH "unknown")' 'set(KYTY_GIT_HASH "${
        lib.substring 0 7 finalAttrs.src.rev
      }")' \
      --replace-fail 'set(KYTY_GIT_REVISION "unknown")' 'set(KYTY_GIT_REVISION "${finalAttrs.src.rev}")'
  '';

  # A pin that no longer matches upstream would be used without a warning.
  preConfigure = ''
    for rev in ${
      lib.concatMapStringsSep " " (source: source.rev) (lib.attrValues fetchContent ++ [ zarchive ])
    }; do
      grep -q "GIT_TAG $rev" 3rdparty/CMakeLists.txt || { echo "stale FetchContent pin $rev"; exit 1; }
    done
    ${notoSans}
    cp -r --no-preserve=mode ${zarchive} build/_deps/zarchive
    ${lib.getExe git} -C build/_deps/zarchive apply --ignore-whitespace $PWD/3rdparty/patches/zarchive-reader.patch
    cmakeFlagsArray+=("-DFETCHCONTENT_SOURCE_DIR_ZARCHIVE_SOURCE=$PWD/build/_deps/zarchive")
  '';

  cmakeFlags = [
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
  ]
  ++ lib.mapAttrsToList (
    name: source: lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_${lib.toUpper name}" "${source}"
  ) fetchContent;

  nativeBuildInputs = [
    cmake
    ninja
    llvmPackages.bintools
    pkg-config
    glslang
    python3
    qt6.wrapQtAppsHook
    makeShellWrapper
    copyDesktopItems
  ];

  buildInputs = runtimeLibraries ++ [
    ffmpeg-headless
    qt6.qtbase
    wayland-protocols
  ];

  # The pipeline cache is keyed on the binary's mtime, which is fixed in the store.
  env.NIX_CFLAGS_COMPILE = "-DKYTY_BUILD_STAMP=0x${lib.substring 0 15 finalAttrs.src.rev}ULL";

  ninjaFlags = [
    "launcher"
    "kyty_emulator"
  ];

  dontWrapQtApps = true;

  installPhase = ''
    runHook preInstall
    cmake --install . --prefix $out/libexec/kytyps5
    rm $out/libexec/kytyps5/kyty_updater
    install -Dm644 ../src/launcher/icons/kyty.svg $out/share/icons/hicolor/scalable/apps/kytyps5.svg
    runHook postInstall
  '';

  # The emulator writes saves, caches and logs to its working directory.
  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath runtimeLibraries} $out/libexec/kytyps5/kyty_emulator
    wrapQtApp $out/libexec/kytyps5/kyty_launcher
    makeShellWrapper $out/libexec/kytyps5/kyty_launcher $out/bin/kytyps5 \
      --run 'dir="''${XDG_DATA_HOME:-$HOME/.local/share}/kytyps5"' \
      --run 'mkdir -p "$dir" && cd "$dir"'
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "kytyps5";
      desktopName = "KytyPS5";
      comment = "PlayStation 5 emulator";
      exec = "kytyps5";
      icon = "kytyps5";
      categories = [
        "Game"
        "Emulator"
      ];
    })
  ];

  passthru.updateScript = writeShellApplication {
    name = "kytyps5-update";
    runtimeInputs = [
      curl
      gnused
      jq
      nix-prefetch-github
    ];
    text = builtins.readFile ./update.sh;
  };

  meta = {
    description = "PlayStation 5 emulator";
    homepage = "https://github.com/KytyPS5/KytyPS5";
    license = with lib.licenses; [
      gpl2Only
      mit
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "kytyps5";
  };
})
