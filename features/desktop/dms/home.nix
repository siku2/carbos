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
        "systemStats"
        "notificationButton"
        "battery"
        "controlCenterButton"
      ];
    };

    plugins.systemStats.enable = true;
    plugins.webSearch.enable = true;
  };
}
