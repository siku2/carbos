{
  lib,
  curl,
  fetchurl,
  gnused,
  jq,
  writeShellApplication,
}:
let
  packageName = "io.homeassistant.companion.android.minimal";
  version = "2026.11.1";
  versionCode = 25506;
in
fetchurl {
  name = "home-assistant-android-${version}.apk";
  # F-Droid moves older versions from repo to archive.
  urls = map (dir: "https://f-droid.org/${dir}/${packageName}_${toString versionCode}.apk") [
    "repo"
    "archive"
  ];
  hash = "sha256-YdlvS8+x+JCqEN1m2+ulX/zeqNmL5WmJNg27/9DoH0k=";

  passthru = {
    inherit packageName versionCode version;

    updateScript = writeShellApplication {
      name = "home-assistant-android-update";
      runtimeInputs = [
        curl
        gnused
        jq
      ];
      text = builtins.readFile ./update.sh;
    };
  };

  meta = {
    description = "Home Assistant Companion for Android, F-Droid build without Google services";
    homepage = "https://companion.home-assistant.io";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
