{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.alt-tab-macos ];

  launchd.user.agents.alt-tab.serviceConfig = {
    ProgramArguments = [
      "${pkgs.alt-tab-macos}/Applications/AltTab.app/Contents/MacOS/AltTab"
    ];
    RunAtLoad = true;
  };

  # AltTab stores every preference as a string.
  system.defaults.CustomUserPreferences."com.lwouis.alt-tab-macos" = {
    holdShortcut = "⌘";
    menubarIconShown = "false";
    # Started by launchd above.
    startAtLogin = "false";
    # Updated through the flake.
    SUEnableAutomaticChecks = false;
  };
}
