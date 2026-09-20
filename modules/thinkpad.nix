{
  config,
  lib,
  ...
}:
let
  cfg = config.carbos.thinkpad.biosSettings;
  attrs = "/sys/class/firmware-attributes/thinklmi/attributes";
in
{
  config = lib.mkIf (cfg != { }) {
    boot.kernelModules = [ "think_lmi" ];

    systemd.services.thinklmi-settings = {
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

        # One rejected setting must not keep the rest from being applied.
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
          fi
        }

        ${lib.concatLines (
          lib.mapAttrsToList (name: value: "apply ${lib.escapeShellArg name} ${lib.escapeShellArg value}") cfg
        )}

        if [ "$changed" = 0 ]; then
          exit 0
        fi

        # Firmware without an admin password rejects save_settings and applies
        # each write directly, so this failing is expected.
        if ! printf '1' > ${attrs}/save_settings 2>/dev/null; then
          echo "save_settings rejected, writes applied directly"
        fi

        if [ "$(cat ${attrs}/pending_reboot)" = "1" ]; then
          echo "BIOS settings changed, reboot to apply"
        fi
      '';
    };
  };
}
