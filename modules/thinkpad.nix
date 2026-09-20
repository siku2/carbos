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

      # One rejected setting must not keep the rest from being applied.
      script = ''
        changed=0

        ${lib.concatLines (
          lib.mapAttrsToList (name: value: ''
            if [ ! -e ${attrs}/${name}/current_value ]; then
              echo "${name}: not offered by this firmware" >&2
            elif [ "$(cat ${attrs}/${name}/current_value)" = "${value}" ]; then
              :
            elif printf '%s' "${value}" > ${attrs}/${name}/current_value; then
              echo "${name}: set to ${value}"
              changed=1
            else
              echo "${name}: write rejected" >&2
            fi
          '') cfg
        )}

        if [ "$changed" = 0 ]; then
          exit 0
        fi

        # Firmware without an admin password applies the write directly and
        # rejects save_settings, so a failure here is not fatal.
        printf '1' > ${attrs}/save_settings || true

        if [ "$(cat ${attrs}/pending_reboot)" = "1" ]; then
          echo "BIOS settings changed, reboot to apply"
        fi
      '';
    };
  };
}
