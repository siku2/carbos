import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { it } from "node:test";
import { promisify } from "node:util";
import {
  description,
  errors,
  implement,
  type Thing,
} from "./fixtures/io.example.Fixture.varlink.ts";
import { VarlinkServer } from "./server.ts";
import { tempSocket } from "./testing.ts";

const thing: Thing = {
  flag: true,
  count: 1,
  ratio: 0.5,
  extra: {},
  tags: ["a", null],
  byName: { a: "fast" },
  inline: { x: 1 },
  mode: "on",
};

const fixture = implement({
  Get: ({ id }) => {
    if (id !== "known") throw errors.Missing({ id });
    return { thing };
  },
  Ping: () => ({}),
});

// Never called, only checked by tsc. The handlers must match the description.
export const wrongTypes = () => [
  implement({
    // @ts-expect-error The output lacks "thing".
    Get: () => ({}),
    Ping: () => ({}),
  }),
  implement({
    Get: () => ({ thing }),
    // @ts-expect-error "()" means no fields.
    Ping: () => ({ extra: 1 }),
  }),
  // @ts-expect-error Ping is missing.
  implement({ Get: () => ({ thing }) }),
  // @ts-expect-error Missing needs an id.
  errors.Missing(),
];

it("embeds the description verbatim", async () => {
  const { readFile } = await import("node:fs/promises");
  const source = await readFile(
    new URL("fixtures/io.example.Fixture.varlink", import.meta.url),
    "utf8",
  );
  assert.equal(description, source);
});

it("serves the generated interface", async () => {
  await using socket = await tempSocket();
  const server = new VarlinkServer({
    info: { vendor: "", product: "", version: "", url: "" },
    interfaces: [fixture],
  });
  await server.listen(socket.path);

  const varlinkctl = (...args: string[]) =>
    promisify(execFile)("varlinkctl", ["--json=short", ...args]);
  const { stdout } = await varlinkctl(
    "call",
    socket.path,
    "io.example.Fixture.Get",
    '{"id":"known"}',
  );
  assert.deepEqual(JSON.parse(stdout), { thing });
  await assert.rejects(
    varlinkctl("call", socket.path, "io.example.Fixture.Get", '{"id":"x"}'),
    { stderr: /io\.example\.Fixture\.Missing/ },
  );
  await server.close();
});
