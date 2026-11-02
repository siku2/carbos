{
  # niri enables gnome-keyring, which would take over SSH_AUTH_SOCK in the user manager.
  flake.modules.nixos.rbw.services.gnome.gcr-ssh-agent.enable = false;

  flake.modules.homeManager.rbw = ./home.nix;
}
