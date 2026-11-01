// Decrypts a fumagician .enc file: AES-256-ECB over a 32 byte header and the
// payload. The header is a magic string followed by the payload length.
import { createDecipheriv } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const magic = Buffer.from("_icianMAG_@*!.8&");

const [key, input, output] = process.argv.slice(2);
if (key === undefined || input === undefined || output === undefined) {
  throw new Error("usage: decrypt.ts <base64 key> <input.enc> <output>");
}

const decipher = createDecipheriv(
  "aes-256-ecb",
  Buffer.from(key, "base64"),
  null,
);
decipher.setAutoPadding(false);
const plain = Buffer.concat([
  decipher.update(readFileSync(input)),
  decipher.final(),
]);

if (!plain.subarray(0, magic.length).equals(magic)) {
  throw new Error(`${input}: wrong key or not a fumagician file`);
}
const length = plain.readUInt32LE(magic.length);
writeFileSync(output, plain.subarray(32, 32 + length));
