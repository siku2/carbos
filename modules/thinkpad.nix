{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.carbos.thinkpad.biosSettings;
  batteryChargeLimit = config.carbos.thinkpad.batteryChargeLimit;
  attrs = "/sys/class/firmware-attributes/thinklmi/attributes";
in
{
  config = {
    services.udev.extraRules = lib.mkIf (batteryChargeLimit != null) ''
      ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT*", ATTR{charge_control_end_threshold}="${toString batteryChargeLimit}"
    '';

    boot.kernelModules = lib.mkIf (cfg != { }) [ "think_lmi" ];

    systemd.services.thinklmi-settings = lib.mkIf (cfg != { }) {
      description = "Apply ThinkPad BIOS settings";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];

      unitConfig.ConditionPathIsDirectory = attrs;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        changed=0
        failed=0

        apply() {
          local name="$1" want="$2"
          local file=${attrs}/$name/current_value

          if [ ! -e "$file" ]; then
            echo "$name: not offered by this firmware" >&2
          elif [ "$(cat "$file")" = "$want" ]; then
            :
          elif printf '%s' "$want" > "$file"; then
            echo "$name: set to $want"
            changed=1
          else
            echo "$name: write rejected" >&2
            failed=1
          fi
        }

        ${lib.concatLines (
          lib.mapAttrsToList (name: value: "apply ${lib.escapeShellArg name} ${lib.escapeShellArg value}") cfg
        )}

        if [ "$changed" = 1 ]; then
          # Firmware without an admin password rejects save_settings and
          # applies each write directly, so this failing is expected.
          if ! printf '1' > ${attrs}/save_settings 2>/dev/null; then
            echo "save_settings rejected, writes applied directly"
          fi

          if [ "$(cat ${attrs}/pending_reboot)" = "1" ]; then
            echo "BIOS settings changed, reboot to apply"
          fi
        fi

        exit "$failed"
      '';
    };

    systemd.user.services.thinklmi-settings-notify = lib.mkIf (cfg != { }) {
      description = "Report the ThinkPad BIOS setting results";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];

      unitConfig.ConditionPathIsDirectory = attrs;

      serviceConfig.Type = "oneshot";

      path = [
        config.systemd.package
        pkgs.libnotify
      ];

      script = ''
        if systemctl is-failed --quiet thinklmi-settings; then
          notify-send --urgency=critical "BIOS settings failed" \
            "Some writes were rejected. See journalctl -u thinklmi-settings."
        elif [ "$(cat ${attrs}/pending_reboot)" = "1" ]; then
          notify-send --urgency=normal "BIOS settings changed" \
            "Reboot to apply them."
        fi
      '';
    };
  };
}
