{ inputs, ... }:
let
  unstable = {
    nixpkgs.overlays = [
      (final: _prev: {
        unstable = import inputs.nixpkgs-unstable {
          system = final.stdenv.hostPlatform.system;
          config = {
            allowUnfree = true;
          };
        };

        # Packages that track unstable on every host.
        inherit (final.unstable)
          _1password-cli
          _1password-gui
          atuin
          chatgpt
          claude-code
          codex
          firefox-bin-unwrapped
          google-chrome
          opencode
          secretspec
          zed-editor
          ;
      })
    ];
  };
in
{
  flake.modules = {
    nixos.unstable = unstable;
    darwin.unstable = unstable;
  };
}
