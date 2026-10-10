import assert from "node:assert/strict";
import { it } from "node:test";
import { parse } from "./idl.ts";
import { invalidField } from "./validate.ts";

const schema = parse(`interface a.b

type Inner (x: int)

method M(
  flag: ?bool,
  ratio: ?float,
  list: ?[]int,
  map: ?[string]string,
  mode: ?(on, off),
  inner: ?Inner,
  any: ?object
) -> ()
`);

const input = schema.methods.get("M")?.input;

const check = (value: Record<string, unknown>) =>
  input && invalidField(schema, input, value);

it("accepts matching values", () => {
  assert.equal(
    check({
      flag: true,
      ratio: 0.5,
      list: [1, 2],
      map: { a: "b" },
      mode: "on",
      inner: { x: 1 },
      any: { whatever: [] },
    }),
    undefined,
  );
  assert.equal(check({}), undefined);
});

it("names the first field that does not match", () => {
  assert.equal(check({ flag: "yes" }), "flag");
  assert.equal(check({ ratio: Number.NaN }), "ratio");
  assert.equal(check({ list: [1, 1.5] }), "list");
  assert.equal(check({ map: { a: 1 } }), "map");
  assert.equal(check({ mode: "maybe" }), "mode");
  assert.equal(check({ inner: { x: 1, y: 2 } }), "inner");
  assert.equal(check({ any: [] }), "any");
  assert.equal(check({ unknown: 1 }), "unknown");
});
