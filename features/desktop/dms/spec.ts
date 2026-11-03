// Prints what the settings builder needs from the DMS sources: the persisted
// settings with their defaults, the settings version and the built-in bar
// widgets. Fails if DMS moved any of them.
import { readFileSync } from "node:fs";
import { join } from "node:path";

interface SpecEntry {
  readonly def: unknown;
  readonly persist?: boolean;
}

const dms = process.argv[2];
if (dms === undefined) throw new Error("usage: spec.ts <dms share directory>");

const read = (path: string): string => readFileSync(join(dms, path), "utf8");

function find(source: string, pattern: RegExp, what: string): string {
  const match = pattern.exec(source)?.[1];
  if (match === undefined) throw new Error(`DMS sources: no ${what} found`);
  return match;
}

// A QML JavaScript library. Without its pragma it is plain JavaScript.
const library = read("Common/settings/SettingsSpec.js").replace(/^\..*$/gm, "");
const spec = new Function(`${library}\nreturn SPEC;`)() as Record<
  string,
  SpecEntry
>;

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
