{
  osConfig,
  pkgs,
  ...
}:
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
    ./gtk.nix
    ./keyring.nix
    ./kicad
    ./mic/module.nix
    ./nextcloud.nix
    ./rbw.nix
    ./vesktop
    ./wallpaper.nix
  ];

  home = {
    # AccountsService falls back to this when no icon is set.
    file.".face".source = ./files/avatar.png;

    packages = with pkgs; [
      bitwarden-cli
      bitwarden-desktop
      file-roller
      git-credential-manager
      inkscape
      libsecret
      nautilus
      nextcloud-talk-desktop
      plexamp
      seahorse
      secretspec
      wl-clipboard
    ];
  };

  xdg.configFile."secretspec/config.toml".source =
    (pkgs.formats.toml { }).generate "secretspec-config.toml"
      {
        defaults.provider = "keyring";
      };

  xdg.userDirs.enable = true;

  programs = {
    foot = {
      enable = true;
      settings = {
        main = {
          font = "${osConfig.carbos.fonts.mono.name}:size=${toString osConfig.carbos.fonts.mono.size}";
        };
      };
    };

    zed-editor.userSettings.buffer_font_family = osConfig.carbos.fonts.mono.name;
  };
}
