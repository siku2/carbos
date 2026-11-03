{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;

  cfg = config.carbos.nextcloud;
  secretspecManifest = ../../secretspec.toml;

  account =
    { name, config, ... }:
    {
      options = {
        server = mkOption {
          type = types.str;
          example = "https://cloud.example.com";
        };

        userId = mkOption {
          type = types.str;
          default = osConfig.carbos.user.login;
          defaultText = lib.literalExpression "osConfig.carbos.user.login";
          description = "Internal user ID, as used in the WebDAV path.";
        };

        login = mkOption {
          type = types.str;
          default = config.userId;
          defaultText = lib.literalExpression "userId";
          description = "Login name. Can differ from the user ID, for example an email address.";
        };

        # A Nextcloud app password, not the login password. Settings > Security.
        passwordSecret = mkOption {
          type = types.str;
          default = "NEXTCLOUD_${lib.toUpper name}_PASSWORD";
          description = "Name of the secretspec secret that holds the app password.";
        };
      };
    };

  calendar = name: account: {
    primary = name == cfg.defaultCalendar.account;
    # With discover, khal names calendars after the collections, so the
    # account name is not a valid default_calendar.
    primaryCollection =
      if name == cfg.defaultCalendar.account then cfg.defaultCalendar.collection else null;

    remote = {
      type = "caldav";
      url = "${account.server}/remote.php/dav/";
      userName = account.login;
      passwordCommand = [
        (lib.getExe pkgs.secretspec)
        "--file"
        "${secretspecManifest}"
        "get"
        account.passwordSecret
        "--caller"
        "vdirsyncer"
        "--reason"
        "vdirsyncer needs the Nextcloud app password to sync the ${name} calendars"
      ];
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
in
{
  options.carbos.nextcloud = {
    accounts = mkOption {
      type = types.attrsOf (types.submodule account);
      default = { };
    };

    defaultCalendar = {
      account = mkOption {
        type = types.enum (lib.attrNames cfg.accounts);
      };

      collection = mkOption {
        type = types.str;
        default = "personal";
      };
    };
  };

  config = {
    carbos.cloud.mounts = lib.mapAttrs (_: account: {
      webdav = {
        url = "${account.server}/remote.php/dav/files/${account.userId}/";
        vendor = "nextcloud";
        user = account.login;
        inherit (account) passwordSecret;
      };
    }) cfg.accounts;

    accounts.calendar.accounts = lib.mapAttrs' (
      name: account: lib.nameValuePair "nextcloud_${name}" (calendar name account)
    ) cfg.accounts;
  };
}
