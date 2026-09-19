{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  server = "https://cloud.bg12.ch";
  user = osConfig.carbos.user.login;

  secretspecManifest = ../../secretspec.toml;
  secretspec = lib.getExe pkgs.unstable.secretspec;

  # A Nextcloud app password, not the login password. Settings > Security.
  password = [
    secretspec
    "--file"
    "${secretspecManifest}"
    "get"
    "NEXTCLOUD_PASSWORD"
    "--caller"
    "vdirsyncer"
    "--reason"
    "vdirsyncer needs the Nextcloud app password to sync the calendar"
  ];

  mountPoint = "${config.home.homeDirectory}/Nextcloud";

  mount = pkgs.writeShellScript "nextcloud-mount" ''
    set -eu
    RCLONE_CONFIG_NC_PASS=$(printf '%s' "$NEXTCLOUD_PASSWORD" | ${lib.getExe pkgs.rclone} obscure -)
    export RCLONE_CONFIG_NC_PASS
    exec ${lib.getExe pkgs.rclone} mount nc: ${mountPoint} \
      --vfs-cache-mode writes \
      --dir-cache-time 30s \
      --poll-interval 1m
  '';
in
{
  accounts.calendar.basePath = ".local/share/calendars";

  accounts.calendar.accounts.nextcloud = {
    primary = true;

    remote = {
      type = "caldav";
      url = "${server}/remote.php/dav/";
      userName = user;
      passwordCommand = password;
    };

    vdirsyncer = {
      enable = true;
      # home-manager maps a to the remote, so collections come "from a".
      collections = [ "from a" ];
      conflictResolution = "remote wins";
    };

    khal = {
      enable = true;
      type = "discover";
    };
  };

  # DMS infers a Qt format by running khal printformats and substituting into
  # the example date, so these have to be explicit and carry the year.
  programs.khal = {
    enable = true;
    locale = {
      dateformat = "%d/%m/%Y";
      longdateformat = "%d/%m/%Y";
      datetimeformat = "%d/%m/%Y %H:%M";
      longdatetimeformat = "%d/%m/%Y %H:%M";
      timeformat = "%H:%M";
      firstweekday = 0;
    };
  };

  programs.vdirsyncer.enable = true;

  services.vdirsyncer = {
    enable = true;
    frequency = "*:0/15";
  };

  home.packages = [ pkgs.rclone ];

  # A mount, not a sync. Nothing is available offline.
  systemd.user.services.nextcloud-mount = {
    Unit = {
      Description = "Nextcloud files";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "notify";
      # secretspec forks, so rclone is not the main pid and would otherwise
      # have its readiness notification rejected.
      NotifyAccess = "all";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${mountPoint}";
      ExecStart = ''
        ${secretspec} --file ${secretspecManifest} run \
          --scope nextcloud \
          --caller nextcloud-mount \
          --reason "rclone needs the Nextcloud app password to mount the drive" \
          -- ${mount}
      '';
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u ${mountPoint}";
      Restart = "on-failure";
      RestartSec = 10;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
