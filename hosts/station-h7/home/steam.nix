{ config, ... }:
{
  # Steam rewrites libraryfolders.vdf on its own, so the library lives here
  # rather than in its config. Everything lands on /games with no setup, and
  # Steam's free space check follows the link to the right subvolume.
  home.file.".local/share/Steam/steamapps".source =
    config.lib.file.mkOutOfStoreSymlink "/games/steamapps";
}
