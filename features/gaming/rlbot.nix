{
  config,
  pkgs,
  ...
}:
{
  # The configured Steam env carries the extra compat tools, so the server
  # can use the Proton picked for Rocket League.
  environment.systemPackages = [
    (pkgs.rlbot.override { steam-run = config.programs.steam.package.run; })
  ];
}
