{ inputs, ... }:
{
  nixpkgs.overlays = [
    (_final: _prev: {
      unstable = import inputs.nixpkgs-unstable {
        system = _final.stdenv.hostPlatform.system;
        config = {
          allowUnfree = true;
        };
      };
    })
  ];
}
