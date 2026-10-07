{
  callPackage,
  coreutils,
  gawk,
  makeDesktopItem,
  steam-run,
  symlinkJoin,
  writeShellApplication,
}:
let
  server = callPackage ./server.nix { };
  gui = callPackage ./gui.nix { };

  # The server starts Rocket League through Proton itself, and the bots are
  # generic Linux binaries, so everything runs in the Steam FHS env.
  launcher = writeShellApplication {
    name = "rlbot-launcher";
    runtimeInputs = [
      coreutils
      gawk
      gui
      server
    ];
    text = builtins.readFile ./launcher.sh;
  };

  rlbot = writeShellApplication {
    name = "rlbot";
    # The FHS env has its own /etc, so a cwd like /etc/nixos does not exist in it.
    text = ''
      cd "$HOME"
      exec ${steam-run}/bin/steam-run ${launcher}/bin/rlbot-launcher "$@"
    '';
  };

  desktopItem = makeDesktopItem {
    name = "rlbot";
    desktopName = "RLBot";
    comment = "Run Rocket League bots";
    exec = "rlbot";
    icon = "rlbot";
    categories = [ "Game" ];
  };
in
symlinkJoin {
  name = "rlbot";
  paths = [
    rlbot
    desktopItem
  ];
  postBuild = ''
    ln -s ${gui}/share/pixmaps $out/share/pixmaps
  '';
  passthru = { inherit server gui; };
  meta.mainProgram = "rlbot";
}
