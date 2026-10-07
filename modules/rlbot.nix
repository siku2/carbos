{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.carbos.rlbot.enable = lib.mkEnableOption "RLBot, with its GUI and server started together";

  config = lib.mkIf config.carbos.rlbot.enable {
    # The configured Steam env carries the extra compat tools, so the server
    # can use the Proton picked for Rocket League.
    environment.systemPackages = [
      (pkgs.rlbot.override { steam-run = config.programs.steam.package.run; })
    ];
  };
}
