{
  programs = {
    starship.settings.gcloud.disabled = true;

    zsh = {
      enable = true;

      oh-my-zsh = {
        enable = true;

        plugins = [
          "git"
          "macos"
          "rust"
        ];
      };
    };
  };
}
