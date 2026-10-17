{ inputs, ... }:
{
  # Composed into the default overlay in packages.nix.
  flake.overlays.unstable =
    final: _prev:
    let
      nixpkgs =
        if final.stdenv.hostPlatform.isDarwin then
          inputs.nixpkgs-unstable-darwin
        else
          inputs.nixpkgs-unstable;
    in
    {
      unstable = import nixpkgs {
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
        rust-analyzer
        secretspec
        teams
        zed-editor
        ;
    };
}
