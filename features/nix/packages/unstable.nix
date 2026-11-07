{ inputs, ... }:
{
  # Composed into the default overlay in default.nix.
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
        chatgpt
        claude-code
        codex
        fan2go
        firefox-bin-unwrapped
        google-chrome
        opencode
        rust-analyzer
        secretspec
        teams
        zed-editor
        ;

      # The atuin-ai session tests fail on darwin and Hydra has no build yet.
      atuin =
        if final.stdenv.hostPlatform.isDarwin then
          final.unstable.atuin.overrideAttrs { doCheck = false; }
        else
          final.unstable.atuin;
    };
}
