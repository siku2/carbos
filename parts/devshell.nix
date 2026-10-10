{ inputs, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    let
      inherit ((pkgs.extend inputs.self.overlays.default).vencord) types;
    in
    {
      devShells.default = pkgs.mkShell {
        packages = [
          config.treefmt.build.wrapper
          pkgs.biome
          pkgs.nil
          pkgs.nixd
          pkgs.nodejs
          pkgs.pnpm_11
        ];

        # Keeps the types in the shell's closure, so the link survives gc.
        VENCORD_TYPES = types;

        shellHook = ''
          ln -sfn "$VENCORD_TYPES" "$(git rev-parse --show-toplevel)/pkgs/vencord/.vencord-types"
        '';
      };
    };
}
