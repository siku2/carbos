{
  lib,
  nodejs,
  vencord,
  vesktop,
  writeShellApplication,
}:
let
  page = builtins.readFile ./discord.html;
  field =
    name:
    let
      match = builtins.match ''.*"${name}":"([^"]+)".*'' page;
    in
    if match == null then throw "discord.html has no ${name}" else builtins.head match;

  discord = {
    build = field "BUILD_NUMBER";
    hash = field "VERSION_HASH";
  };

  # Our Vencord carries the local plugins.
  base = vesktop.override {
    inherit vencord;
    withSystemVencord = true;
  };

  app = {
    name = "vesktop";
    inherit (vesktop) version;
    type = "module";
    main = "main.ts";
  };
in
base.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    pinned=$out/opt/Vesktop/resources/pinned
    install -Dm444 ${./main.ts} $pinned/main.ts
    install -Dm444 ${./discord.html} $pinned/discord.html
    echo ${lib.escapeShellArg (builtins.toJSON app)} > $pinned/package.json
    echo ${
      lib.escapeShellArg (
        builtins.toJSON {
          inherit (discord) hash;
          required = false;
        }
      )
    } > $pinned/version.json
  '';

  postFixup = old.postFixup + ''
    substituteInPlace $out/bin/vesktop \
      --replace-fail $out/opt/Vesktop/resources/app.asar $out/opt/Vesktop/resources/pinned
  '';

  passthru = old.passthru // {
    inherit discord;
    updateScript = writeShellApplication {
      name = "vesktop-update";
      runtimeInputs = [ nodejs ];
      text = ''node ${./update.ts} "$@"'';
    };
  };

  meta = old.meta // {
    platforms = lib.platforms.linux;
  };
})
