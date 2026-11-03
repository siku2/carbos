{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  dir = "Cloud";
  mountRoot = "${config.xdg.stateHome}/cloud";

  secretspecManifest = ../../secretspec.toml;
  secretspec = lib.getExe pkgs.secretspec;
  rclone = lib.getExe pkgs.rclone;

  webdav = {
    url = mkOption {
      type = types.str;
    };
    vendor = mkOption {
      type = types.enum [
        "fastmail"
        "nextcloud"
        "owncloud"
        "infinitescale"
        "sharepoint"
        "sharepoint-ntlm"
        "rclone"
        "other"
      ];
      default = "other";
    };
    user = mkOption {
      type = types.str;
    };
    passwordSecret = mkOption {
      type = types.str;
      description = "Name of the secretspec secret that holds the password.";
    };
  };

  mountScript =
    name: mount:
    pkgs.writeShellScript "cloud-${name}" ''
      set -eu
      export RCLONE_CONFIG_REMOTE_TYPE=webdav
      export RCLONE_CONFIG_REMOTE_URL=${lib.escapeShellArg mount.webdav.url}
      export RCLONE_CONFIG_REMOTE_VENDOR=${mount.webdav.vendor}
      export RCLONE_CONFIG_REMOTE_USER=${lib.escapeShellArg mount.webdav.user}
      password=$(${secretspec} --file ${secretspecManifest} get ${mount.webdav.passwordSecret} \
        --caller cloud-${name} \
        --reason "rclone needs the password to mount ${name}")
      RCLONE_CONFIG_REMOTE_PASS=$(printf '%s' "$password" | ${rclone} obscure -)
      export RCLONE_CONFIG_REMOTE_PASS
      exec ${rclone} mount remote: ${mountRoot}/${name} \
        --vfs-cache-mode writes \
        --dir-cache-time 30s \
        --poll-interval 1m
    '';

  # A mount, not a sync. Nothing is available offline.
  mountService = name: mount: {
    Unit = {
      Description = "Cloud mount ${name}";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "notify";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mountRoot}/${name}";
      ExecStart = mountScript name mount;
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u ${mountRoot}/${name}";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
in
{
  options.carbos.cloud.mounts = mkOption {
    type = types.attrsOf (types.submodule { options = { inherit webdav; }; });
    default = { };
    description = "Remote storage, each linked at ~/Cloud/<name>.";
  };

  config = {
    home.packages = [ pkgs.rclone ];

    home.file = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "${dir}/${name}" {
        source = config.lib.file.mkOutOfStoreSymlink "${mountRoot}/${name}";
      }
    ) config.carbos.cloud.mounts;

    systemd.user.services = lib.mapAttrs' (
      name: mount: lib.nameValuePair "cloud-${name}" (mountService name mount)
    ) config.carbos.cloud.mounts;
  };
}
