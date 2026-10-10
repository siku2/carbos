// Prints what the settings builder needs from the DMS sources: the persisted
// settings with their defaults, the settings version and the built-in bar
// widgets. Fails if DMS moved any of them.
import { readFileSync } from "node:fs";
import { join } from "node:path";

const read = (path) => readFileSync(join(process.argv[2], path), "utf8");

function find(source, pattern, what) {
  const match = pattern.exec(source);
  if (match === null) throw new Error(`DMS sources: no ${what} found`);
  return match[1];
}

// A QML JavaScript library. Without its pragma it is plain JavaScript.
const library = read("Common/settings/SettingsSpec.js").replace(/^\..*$/gm, "");
const spec = new Function(`${library}\nreturn SPEC;`)();

const defaults = Object.fromEntries(
  Object.entries(spec)
    .filter(([, entry]) => entry.persist !== false)
    .map(([key, entry]) => [key, entry.def]),
);

const configVersion = Number(
  find(
    read("Common/SettingsData.qml"),
    /settingsConfigVersion:\s*(\d+)/,
    "settings version",
  ),
);

const widgetMap = find(
  read("Modules/DankBar/DankBarContent.qml"),
  /let baseMap = \{([^}]*)\}/,
  "bar widgets",
);
const widgets = Array.from(
  widgetMap.matchAll(/"(\w+)":/g),
  (match) => match[1],
);
if (widgets.length === 0) throw new Error("DMS sources: no bar widgets found");

console.log(JSON.stringify({ defaults, configVersion, widgets }));
