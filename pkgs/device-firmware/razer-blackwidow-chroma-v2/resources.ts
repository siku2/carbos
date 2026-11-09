// Writes the Intel HEX image from Razer's DeviceUpdater.resources, a .NET
// resources file that holds it as one string per line, and prints the
// firmware version it names.
import { readFileSync, writeFileSync } from "node:fs";

const magic = 0xbeefcace;
const int32Type = 8;
const stringType = 1;

const [input, output] = process.argv.slice(2);
if (input === undefined || output === undefined) {
  throw new Error("usage: resources.ts <DeviceUpdater.resources> <image.hex>");
}

const file = readFileSync(input);
let offset = 0;

function int32(): number {
  const value = file.readInt32LE(offset);
  offset += 4;
  return value;
}

// .NET writes lengths and type codes as 7 bit encoded integers.
function varint(): number {
  let value = 0;
  for (let shift = 0; ; shift += 7) {
    const byte = file.readUInt8(offset++);
    value |= (byte & 0x7f) << shift;
    if ((byte & 0x80) === 0) return value;
  }
}

function string(encoding: "utf8" | "utf16le"): string {
  const length = varint();
  const value = file.toString(encoding, offset, offset + length);
  offset += length;
  return value;
}

if (file.readUInt32LE(0) !== magic) {
  throw new Error(`${input}: not a .NET resources file`);
}
offset = 12 + file.readInt32LE(8);
int32();
const count = int32();
const typeCount = int32();
for (let i = 0; i < typeCount; i++) string("utf8");
offset = (offset + 7) & ~7;
offset += 4 * count;
const namePositions = Array.from({ length: count }, int32);
const dataStart = int32();
const namesStart = offset;

const values = new Map<string, string | number>();
for (const position of namePositions) {
  offset = namesStart + position;
  const name = string("utf16le");
  offset = dataStart + int32();
  const type = varint();
  if (type === stringType) values.set(name, string("utf8"));
  if (type === int32Type) values.set(name, int32());
}

function get(name: string): string | number {
  const value = values.get(name);
  if (value === undefined) throw new Error(`${input}: no ${name}`);
  return value;
}

const lines = Array.from({ length: Number(get("DevFWLineNum")) }, (_, i) =>
  get(`DevFWLine${i}`),
);
writeFileSync(output, `${lines.join("\n")}\n`);
console.log(get("DevFWVer"));
