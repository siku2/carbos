{
  programs = {
    starship = {
      enable = true;
      settings.gcloud.disabled = true;
    };

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

      shellAliases = {
        x = "cargo run --quiet --bin xtask --";
        zed = "zeditor";
      };
    };
  };
}
