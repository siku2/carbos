{ lib, pkgs, ... }:
let
  inherit (lib) mkOption types;

  json = pkgs.formats.json { };

  marketplaceSource = types.submodule {
    options.source = mkOption {
      type = types.enum [ "skills-dir" ];
      description = "`skills-dir` is ~/.claude/skills, which any allowlist blocks unless listed.";
    };
  };
in
{
  options.carbos.claudeCode.managedSettings = mkOption {
    type = types.submodule {
      options.strictKnownMarketplaces = mkOption {
        type = types.nullOr (types.listOf marketplaceSource);
        default = null;
        description = "Marketplace sources Claude Code may use. Null allows all of them.";
      };
    };
    default = { };
    apply =
      settings:
      json.generate "managed-settings.json" (lib.filterAttrs (_: value: value != null) settings);
  };
}
