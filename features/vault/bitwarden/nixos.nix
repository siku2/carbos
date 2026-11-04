{ config, lib, ... }:
{
  # niri enables gnome-keyring, which would take over SSH_AUTH_SOCK in the user manager.
  services.gnome.gcr-ssh-agent.enable = lib.mkIf (config.carbos.vault.backend == "bitwarden") false;
}
