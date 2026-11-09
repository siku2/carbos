// Extracts a G HUB depot: a magic number, a JSON file list, then each file
// as a length and its bytes.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, normalize } from "node:path";

const magic = 0x20170110;

const [input, output] = process.argv.slice(2);
if (input === undefined || output === undefined) {
  throw new Error("usage: depot.ts <file.depot> <directory>");
}

const depot = readFileSync(input);
if (depot.readUInt32LE(0) !== magic) {
  throw new Error(`${input}: not a G HUB depot`);
}
const headerEnd = 8 + depot.readUInt32LE(4);
const header = JSON.parse(depot.subarray(8, headerEnd).toString()) as {
  files: { name: string }[];
};

let offset = headerEnd;
for (const { name } of header.files) {
  const path = normalize(name);
  if (path.startsWith("..") || path.startsWith("/")) {
    throw new Error(`${input}: unsafe path ${name}`);
  }
  const length = depot.readUInt32LE(offset);
  offset += 4;
  mkdirSync(dirname(join(output, path)), { recursive: true });
  writeFileSync(join(output, path), depot.subarray(offset, offset + length));
  offset += length;
}
if (offset !== depot.length) {
  throw new Error(`${input}: ${depot.length - offset} trailing bytes`);
}
