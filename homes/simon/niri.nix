{
  lib,
  pkgs,
  ...
}:
let
  seedFragments = pkgs.writeShellApplication {
    name = "niri-dms-fragments";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./niri-dms-fragments.sh;
  };
in
{
  xdg.configFile."niri/config.kdl".source = ./files/niri.kdl;

  home.activation.dmsNiriFragments = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    FRAGMENT_DIR=${lib.escapeShellArg "${./files/niri-dms}"} \
    run ${lib.getExe seedFragments}
  '';
}
