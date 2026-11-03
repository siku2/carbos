{ pkgs, ... }:
{
  home.packages = with pkgs; [
    age
    fd
    fzf
    jq
    python3
    ripgrep
    sops
    tree
    unzip
    wget
    yq
  ];
}
