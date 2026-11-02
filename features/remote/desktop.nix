{ lib, pkgs, ... }:
let
  port = 5900;
  # Differs from port, so a host can serve and view at the same time.
  localPort = 5901;

  remoteDesktop = pkgs.writeShellApplication {
    name = "remote-desktop";
    runtimeInputs = [
      pkgs.openssh
      pkgs.wlvncc
    ];
    text = ''
      # ssh stays up until the viewer closes its connection.
      ssh -f -o ExitOnForwardFailure=yes -o ServerAliveInterval=10 \
        -L ${toString localPort}:localhost:${toString port} "$1" sleep 10
      exec wlvncc --shortcut-inhibit localhost ${toString localPort}
    '';
  };
in
{
  # Without auth, so it only listens on localhost and is reached through ssh.
  systemd.user.sockets.wayvnc = {
    description = "VNC server for the session";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    socketConfig.ListenStream = "127.0.0.1:${toString port}";
  };

  systemd.user.services.wayvnc = {
    description = "VNC server for the session";
    serviceConfig.ExecStart = "${lib.getExe pkgs.wayvnc} --gpu --exit-on-disconnect fd:3";
  };

  environment.systemPackages = [ remoteDesktop ];
}
