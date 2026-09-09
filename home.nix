{ pkgs, ... }:

{
  home.username = "simon";
  home.stateVersion = "26.05";

  programs = {
    git = {
      enable = true;
      lfs.enable = true;
    };

    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;
    };

    starship.enable = true;

    bash.enable = true;
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
      };
    };
  };

  home.packages = with pkgs; [
    age
    fd
    fzf
    jq
    nixd
    nil
    nixfmt
    ripgrep
    sops
    tree
    unzip
    wget
    yq
  ];
}
