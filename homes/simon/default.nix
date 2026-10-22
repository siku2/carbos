{ pkgs, ... }:
{
  imports = [
    ./ai.nix
    ./ardour
    ./atuin.nix
    ./bitwarden.nix
    ./dsearch.nix
    ./firefox.nix
    ./fractal.nix
    ./git.nix
    ./kicad
    ./mic/module.nix
    ./nextcloud.nix
    ./rbw.nix
    ./vesktop
    ./wallpaper.nix
  ];

  home.packages = with pkgs; [
    bitwarden-cli
    bitwarden-desktop
    git-credential-manager
    nextcloud-talk-desktop
    secretspec
  ];

  xdg.configFile."secretspec/config.toml".source =
    (pkgs.formats.toml { }).generate "secretspec-config.toml"
      {
        defaults.provider = "keyring";
      };
}
