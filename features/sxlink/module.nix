{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.sxlink;

  device.options = {
    server = mkOption {
      type = types.str;
      description = "Host name or address of the Silex device server.";
    };
    match = mkOption {
      type = types.str;
      description = "Server port name, like usb4-003:0, or the USB serial number.";
    };
  };

  # The server announces the device from a random port to UDP 19540, so
  # conntrack doesn't match it to our request. Open it while attached only.
  firewall =
    name: server:
    pkgs.writeShellApplication {
      name = "sxlink-${name}-firewall";
      runtimeInputs = [
        config.networking.firewall.package
        pkgs.getent
        pkgs.gawk
        pkgs.gnugrep
      ];
      text = ''
        tag="sxlink-${name}"
        for cmd in iptables ip6tables; do
          "$cmd" -S nixos-fw | { grep -F -- "--comment $tag " || true; } | while read -r _ chain rule; do
            eval "$cmd -D $chain $rule"
          done
        done
        [ "$1" = open ] || exit 0
        getent ahosts ${lib.escapeShellArg server} | awk '{ print $1 }' | sort -u | while read -r addr; do
          cmd=iptables
          case "$addr" in *:*) cmd=ip6tables ;; esac
          "$cmd" -I nixos-fw -s "$addr" -p udp --dport 19540 -m comment --comment "$tag" -j nixos-fw-accept
        done
      '';
    };
in
{
  options.carbos.sxlink.devices = mkOption {
    type = types.attrsOf (types.submodule device);
    default = { };
    description = "Devices to attach on demand with `systemctl start sxlink-<name>`.";
  };

  config = lib.mkIf (cfg.devices != { }) {
    boot.kernelModules = [ "vhci-hcd" ];

    systemd.services = lib.mapAttrs' (
      name: device:
      let
        fw = lib.getExe (firewall name device.server);
      in
      lib.nameValuePair "sxlink-${name}" {
        description = "Attach ${name} from ${device.server}";
        after = [
          "firewall.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStartPre = "${fw} open";
          ExecStart = "${lib.getExe pkgs.sxlink} attach ${device.server} ${device.match} --take";
          ExecStopPost = "${fw} close";
          Restart = "on-failure";
          RestartSec = 5;
        };
      }
    ) cfg.devices;
  };
}
