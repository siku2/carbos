{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.carbos.remote.desktop;

  port = 5900;
  # Differs from port, so a host can serve and view at the same time.
  localPort = 5901;

  niriOutput =
    name: text:
    pkgs.writeShellApplication {
      inherit name text;
      runtimeInputs = [
        config.programs.niri.package
        pkgs.jq
      ];
    };

  # niri keeps transient output changes across config reloads, so the
  # previous mode and scale are saved and restored explicitly.
  enter = niriOutput "wayvnc-enter" ''
    niri msg -j outputs | jq -r --arg o "$1" '
      .[] | select(.name == $o or "\(.make) \(.model) \(.serial)" == $o)
      | "\(.modes[.current_mode] | "\(.width)x\(.height)@\(.refresh_rate / 1000)") \(.logical.scale)"
    ' >"$RUNTIME_DIRECTORY/output"
    niri msg output "$1" mode "$2"
    niri msg output "$1" scale "$3"
  '';

  leave = niriOutput "wayvnc-leave" ''
    read -r mode scale <"$RUNTIME_DIRECTORY/output"
    niri msg output "$1" mode "$mode"
    niri msg output "$1" scale "$scale"
  '';

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
  options.carbos.remote.desktop.output = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          mode = lib.mkOption { type = lib.types.str; };
          scale = lib.mkOption { type = lib.types.number; };
        };
      }
    );
    default = null;
    description = ''
      Output to switch to another mode while a viewer is connected.
      GPU encoding only handles up to 4096 pixels per side.
    '';
  };

  config = {
    # Without auth, so it only listens on localhost and is reached through ssh.
    systemd.user.sockets.wayvnc = {
      description = "VNC server for the session";
      partOf = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      socketConfig.ListenStream = "127.0.0.1:${toString port}";
    };

    systemd.user.services.wayvnc = {
      description = "VNC server for the session";
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.wayvnc} --gpu --exit-on-disconnect fd:3";
      }
      // lib.optionalAttrs (cfg.output != null) {
        RuntimeDirectory = "wayvnc";
        ExecStartPre = lib.escapeShellArgs [
          (lib.getExe enter)
          cfg.output.name
          cfg.output.mode
          (toString cfg.output.scale)
        ];
        ExecStopPost = lib.escapeShellArgs [
          (lib.getExe leave)
          cfg.output.name
        ];
      };
    };

    environment.systemPackages = [ remoteDesktop ];
  };
}
