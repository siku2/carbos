{
  config,
  pkgs,
  ...
}:
{
  fonts.packages = [
    pkgs.inter
    config.carbos.fonts.mono.package
  ];

  fonts.fontconfig.defaultFonts = {
    monospace = [ config.carbos.fonts.mono.name ];
    sansSerif = [ "Inter" ];
  };
}
