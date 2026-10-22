{ pkgs, ... }:
{
  home.packages = [ pkgs.secretspec ];

  xdg.configFile."secretspec/config.toml".source =
    (pkgs.formats.toml { }).generate "secretspec-config.toml"
      {
        defaults.provider = "keyring";
      };
}
