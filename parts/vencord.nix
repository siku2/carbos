{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.vencord-plugins = (pkgs.extend inputs.self.overlays.default).vencord.workspace;
    };
}
