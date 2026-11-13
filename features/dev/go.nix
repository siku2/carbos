{ config, ... }:
{
  programs.go = {
    enable = true;
    # Projects bring their own toolchain through dev shells.
    package = null;
    env = {
      GOPATH = "${config.xdg.dataHome}/go";
      GOMODCACHE = "${config.xdg.cacheHome}/go/mod";
      GOBIN = "/go-install-is-disabled-use-nix";
    };
  };
}
