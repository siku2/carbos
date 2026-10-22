{
  imports = [ ./module.nix ];

  carbos.vesktop = {
    discordBranch = "stable";
    minimizeToTray = true;
    arRPC = true;
    hardwareVideoAcceleration = true;
    enableSplashScreen = false;

    plugins.YoutubeAdblock.enable = true;

    # DMS renders it from the wallpaper colors.
    themes = [ "dank-discord.css" ];
  };
}
