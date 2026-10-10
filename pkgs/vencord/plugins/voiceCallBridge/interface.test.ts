import { execFile } from "node:child_process";
import { it } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

it("has a valid interface description", async () => {
  const file = fileURLToPath(
    new URL("io.siku2.VoiceCall.varlink", import.meta.url),
  );
  await promisify(execFile)("varlinkctl", ["validate-idl", file]);
});
