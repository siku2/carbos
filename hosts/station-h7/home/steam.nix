{ config, ... }:
{
  # Steam rewrites libraryfolders.vdf itself, so use a symlink instead.
  home.file.".local/share/Steam/steamapps".source =
    config.lib.file.mkOutOfStoreSymlink "/games/steamapps";
}
