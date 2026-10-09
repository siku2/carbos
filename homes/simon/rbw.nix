{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  sshAuthSock = "\${XDG_RUNTIME_DIR}/rbw/ssh-agent-socket";

  # SSH agent requests carry no environment, so rbw-agent reuses the one from
  # the last rbw command. Until then pinentry has no display and fails.
  primeAgent = pkgs.writeShellScript "rbw-agent-prime" ''
    for _ in $(seq 50); do
      [ -S "$XDG_RUNTIME_DIR/rbw/socket" ] && break
      sleep 0.1
    done
    ${lib.getExe config.programs.rbw.package} unlocked || true
  '';
in
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
      ExecStartPost = "${primeAgent}";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # home.sessionVariables only reaches login shells. Apps launched from the
  # shell inherit from the systemd user manager, which reads environment.d.
  home.sessionVariables.SSH_AUTH_SOCK = sshAuthSock;
  systemd.user.sessionVariables.SSH_AUTH_SOCK = sshAuthSock;
}
