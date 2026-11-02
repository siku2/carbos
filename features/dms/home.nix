{ config, lib, ... }:
{
  imports = [ ./module.nix ];

  carbos.dms = {
    settings = {
      appIdSubstitutions = [ ];
      controlCenterShowMicPercent = true;
      osdPowerProfileEnabled = true;
      powerMenuActions = [
        "reboot"
        "logout"
        "poweroff"
        "lock"
        "monitorsoff"
        "suspend"
        "restart"
      ];
    };

    bars.default = {
      left = [
        "launcherButton"
        "workspaceSwitcher"
        "focusedWindow"
      ];
      center = [
        "music"
        "clock"
        "weather"
      ];
      right = [
        "systemTray"
        "clipboard"
        "cpuUsage"
        "memUsage"
      ]
      ++ lib.optional (config.carbos.dms.plugins.gpuUsage.enable or false) "gpuUsage"
      ++ [
        "notificationButton"
        "battery"
        "controlCenterButton"
      ];
    };

    plugins.webSearch.enable = true;
  };
}
