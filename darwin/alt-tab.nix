{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.system.primaryUser;

  shortcuts = {
    holdShortcut.modifiers = [ "command" ];
    previousWindowShortcut = {
      modifiers = [ "shift" ];
      key = "tab";
    };
  };

  keys = {
    tab = {
      code = 48;
      symbol = "⇥";
    };
  };

  modifierFlags = {
    shift = {
      flag = 131072;
      symbol = "⇧";
    };
    control = {
      flag = 262144;
      symbol = "⌃";
    };
    option = {
      flag = 524288;
      symbol = "⌥";
    };
    command = {
      flag = 1048576;
      symbol = "⌘";
    };
  };

  uid = n: { "CF$UID" = n; };

  # AltTab stores a shortcut as an NSKeyedArchiver archive of a
  # ShortcutRecorder SRShortcut. This is that archive as an XML plist, which
  # plutil turns into the binary form during activation.
  shortcutArchive =
    name:
    {
      modifiers ? [ ],
      key ? null,
    }:
    pkgs.writeText "alt-tab-${name}.plist" (
      lib.generators.toPlist { escape = true; } {
        "$archiver" = "NSKeyedArchiver";
        "$version" = 100000;
        "$top".root = uid 1;
        "$objects" = [
          "$null"
          {
            "$class" = uid 5;
            # Only used for display. Shortcuts are matched on keyCode and
            # modifierFlags.
            characters = uid (if key == null then 0 else 6);
            charactersIgnoringModifiers = uid (if key == null then 0 else 6);
            keyCode = uid 3;
            modifierFlags = uid 4;
            version = uid 2;
          }
          "1"
          (if key == null then 65535 else keys.${key}.code)
          (lib.foldl' builtins.bitOr 0 (map (m: modifierFlags.${m}.flag) modifiers))
          {
            "$classes" = [
              "SRShortcut"
              "NSObject"
            ];
            "$classname" = "SRShortcut";
          }
        ]
        ++ lib.optional (key != null) keys.${key}.symbol;
      }
    );

  shortcutString =
    {
      modifiers ? [ ],
      key ? null,
    }:
    lib.concatMapStrings (m: modifierFlags.${m}.symbol) modifiers
    + lib.optionalString (key != null) keys.${key}.symbol;

  writeShortcut = name: shortcut: ''
    data=$(/usr/bin/plutil -convert binary1 -o - ${shortcutArchive name shortcut} | /usr/bin/base64)
    launchctl asuser "$(id -u -- ${user})" sudo --user=${user} -- \
      defaults write com.lwouis.alt-tab-macos ${name} \
      "<dict><key>secureData</key><data>$data</data><key>string</key><string>${shortcutString shortcut}</string></dict>"
  '';
in
{
  environment.systemPackages = [ pkgs.alt-tab-macos ];

  launchd.user.agents.alt-tab.serviceConfig = {
    ProgramArguments = [
      "${pkgs.alt-tab-macos}/Applications/AltTab.app/Contents/MacOS/AltTab"
    ];
    RunAtLoad = true;
  };

  # Leave the vertical swipes to AltTab instead of Mission Control.
  system.defaults = {
    dock = {
      showMissionControlGestureEnabled = false;
      showAppExposeGestureEnabled = false;
    };
    trackpad = {
      TrackpadThreeFingerVertSwipeGesture = 0;
      TrackpadFourFingerVertSwipeGesture = 0;
    };
  };

  # AltTab stores most preferences as strings.
  system.defaults.CustomUserPreferences."com.lwouis.alt-tab-macos" = {
    menubarIconShown = "false";
    # 3-finger vertical swipe.
    nextWindowGesture = "2";
    # Started by launchd above.
    startAtLogin = "false";
    # Updated through the flake.
    SUEnableAutomaticChecks = false;
  };

  # CustomUserPreferences can't write the binary shortcut data.
  system.activationScripts.userDefaults.text = lib.mkAfter (
    lib.concatStrings (lib.mapAttrsToList writeShortcut shortcuts)
  );
}
