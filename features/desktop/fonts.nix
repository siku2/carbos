{ config, ... }:
{
  fonts.fontconfig.defaultFonts = {
    monospace = [ config.carbos.fonts.mono.name ];
    sansSerif = [ "Inter" ];
  };
}
