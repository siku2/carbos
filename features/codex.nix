let
  # Codex writes to ~/.codex/config.toml itself, so set this in the system layer.
  # Move it to programs.codex.mutableSettings once Home Manager releases it.
  system.environment.etc."codex/config.toml".text = ''
    check_for_update_on_startup = false
  '';
in
{
  flake.modules.nixos.codex = system;
  flake.modules.darwin.codex = system;
  flake.modules.homeManager.codex.programs.codex.enable = true;
}
