import { glob, readFile, writeFile } from "node:fs/promises";
import { basename } from "node:path";
import { generate } from "./codegen.ts";

// Writes <name>.varlink.ts next to every <name>.varlink below the working
// directory. With --check, only reports the ones that are out of date.
const check = process.argv.includes("--check");
const skipped = new Set(["node_modules", ".vencord-types"]);

let stale = 0;
for await (const file of glob("**/*.varlink", {
  exclude: (path) => skipped.has(basename(path)),
})) {
  const target = `${file}.ts`;
  const output = generate(await readFile(file, "utf8"), {
    file: basename(file),
    runtime: "@carbos/varlink",
  });
  if (!check) {
    await writeFile(target, output);
  } else if ((await readFile(target, "utf8").catch(() => "")) !== output) {
    console.error(`${target} is out of date. Run "pnpm run generate".`);
    stale++;
  }
}
if (stale > 0) process.exitCode = 1;
