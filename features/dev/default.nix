{
  imports = [ ./zed.nix ];

  flake.modules.homeManager.dev =
    { pkgs, ... }:
    {
      imports = [ ./rust.nix ];

      home.packages = [
        pkgs.ansifilter
        pkgs.devcontainer
      ];
    };
}
