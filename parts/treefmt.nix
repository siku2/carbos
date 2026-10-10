{ inputs, lib, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem.treefmt.programs = {
    biome = {
      enable = true;
      # The editor reads biome.json directly. treefmt picks the files itself, and
      # the config lands in the store, away from the ignore file.
      settings = lib.recursiveUpdate (lib.importJSON ../biome.json) { vcs.enabled = false; };
    };
    deadnix.enable = true;
    nixfmt.enable = true;
    shellcheck.enable = true;
    shfmt.enable = true;
    statix.enable = true;
  };
}
