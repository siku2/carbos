{
  # Codex writes to ~/.codex/config.toml itself, so set this in the system layer.
  # Move it to programs.codex.mutableSettings once Home Manager releases it.
  environment.etc."codex/config.toml".text = ''
    check_for_update_on_startup = false
  '';
}
