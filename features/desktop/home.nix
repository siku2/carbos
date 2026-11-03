{
  osConfig,
  pkgs,
  ...
}:
{
  imports = [
    ./gtk.nix
    ./keyring.nix
  ];

  home = {
    # AccountsService falls back to this when no icon is set.
    file.".face".source = ./avatar.png;

    packages = with pkgs; [
      file-roller
      # No tray and no background mode, so notifications only arrive while a
      # window is open.
      fractal
      inkscape
      libsecret
      nautilus
      plexamp
      seahorse
      wl-clipboard
    ];
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
