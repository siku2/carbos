{ inputs, ... }:
{
  nixpkgs.overlays = [
    (final: _prev: {
      unstable = import inputs.nixpkgs-unstable {
        system = final.stdenv.hostPlatform.system;
        config = {
          allowUnfree = true;
        };
      };

      # Shared home modules use the plain names and expect current releases.
      claude-code = final.unstable.claude-code;
      codex = final.unstable.codex;
    })
  ];
}
