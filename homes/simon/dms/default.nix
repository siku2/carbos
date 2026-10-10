{
  imports = [ ./module.nix ];

  carbos.dms = {
    settings = {
      appIdSubstitutions = [ ];
      controlCenterShowMicPercent = true;
      osdPowerProfileEnabled = true;
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
        "notificationButton"
        "battery"
        "controlCenterButton"
      ];
    };

    plugins.webSearch.enable = true;
  };
}
