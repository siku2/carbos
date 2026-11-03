let
  # Codex writes to ~/.codex/config.toml itself, so set this in the system layer.
  # Move it to programs.codex.mutableSettings once Home Manager releases it.
  system.environment.etc."codex/config.toml".text = ''
    check_for_update_on_startup = false
  '';
in
{
  flake.modules.nixos.agents = system;
  flake.modules.darwin.agents = system;
  flake.modules.homeManager.agents.programs.codex.enable = true;
}
