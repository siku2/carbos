# Turns the declared settings into settings.json. Fails on anything DMS would
# silently ignore.

def fail($message): error("DMS settings: " + $message);

def known($keys; $allowed; $what):
  ($keys - $allowed) as $unknown
  | if ($unknown | length) > 0
    then fail("unknown " + $what + ": " + ($unknown | join(", ")))
    else .
    end;

$spec[0] as $spec
# A bar gets no defaults from DMS, only the whole list does.
| $spec.defaults.barConfigs[0] as $barDefaults
| ($spec.widgets + .pluginWidgets) as $widgets
| known(.settings | keys; $spec.defaults | keys - ["barConfigs"]; "settings")
| .settings + {
    configVersion: $spec.configVersion,
    barConfigs: [
      .bars | to_entries[] | .key as $id | .value
      | known(
          .settings | keys;
          $barDefaults | keys - ["id", "leftWidgets", "centerWidgets", "rightWidgets"];
          "settings of bar " + $id
        )
      | known(
          [.left, .center, .right] | add | map(if type == "string" then . else .id end);
          $widgets;
          "widgets in bar " + $id
        )
      | $barDefaults
        + { id: $id }
        + .settings
        + { leftWidgets: .left, centerWidgets: .center, rightWidgets: .right }
    ]
  }
