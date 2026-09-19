{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
{
  programs.rbw = {
    enable = true;
    settings = {
      email = osConfig.carbos.user.email;
      base_url = "https://vault.bg12.ch";

      # Setting sso_id is what makes rbw use the authorization_code flow at all.
      # Vaultwarden has a single IdP and its /sso/prevalidate ignores the value.
      sso_id = "vaultwarden";
      # Without this rbw opens the SSO page on vault.bitwarden.com.
      ui_url = "https://vault.bg12.ch";
      # gcr is not on the session bus, so pinentry-gnome3 would drop to curses.
      pinentry = pkgs.pinentry-qt;
      lock_timeout = 28800;
    };
  };

  # rbw-agent serves the SSH agent protocol itself and decrypts the key per
  # signature, prompting through pinentry when the vault is locked.
  systemd.user.services.rbw-agent = {
    Unit = {
      Description = "rbw agent";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe' config.programs.rbw.package "rbw-agent"} --no-daemonize";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/rbw/ssh-agent-socket";
}
