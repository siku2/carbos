{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./module.nix ];

  carbos.nextcloud = {
    accounts = {
      bg12.server = "https://cloud.bg12.ch";
      stargrid = {
        server = "https://nextcloud.stargrid.systems";
        login = "simon@siku2.io";
      };
    };
    defaultCalendar.account = "bg12";
  };

  accounts.calendar.basePath = ".local/share/calendars";

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

  # The upstream unit only runs metasync and sync, both of which refuse to run
  # until collections have been discovered. Repeating it picks up new calendars.
  systemd.user.services.vdirsyncer.Service.ExecStartPre = [
    # yes is left holding a closed pipe once discover exits, so drop its stderr.
    "${lib.getExe pkgs.bash} -c 'yes 2>/dev/null | ${lib.getExe config.services.vdirsyncer.package} discover'"
  ];

  home.packages = [ pkgs.nextcloud-talk-desktop ];
}
