import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { IdlError, parse } from "./idl.ts";

describe("parse", () => {
  it("reads every kind of member and type", () => {
    const schema = parse(`# The interface.
interface org.example.Test-Two

# A type.
type Thing (
  # A field.
  flag: bool,
  count: int,
  ratio: float,
  label: ?string,
  extra: object,
  list: []?string,
  map: [string]Thing,
  mode: (on, off),
  inner: (x: int)
)

type Mode (fast, slow)

method Get(id: string) -> (thing: Thing)

# Two lines
# of documentation.
error Missing (id: string)
`);
    assert.equal(schema.name, "org.example.Test-Two");
    assert.equal(schema.doc, "The interface.");
    assert.deepEqual(schema.types.get("Mode")?.type, {
      kind: "enum",
      values: ["fast", "slow"],
    });
    assert.deepEqual(schema.types.get("Thing")?.type, {
      kind: "struct",
      fields: [
        { name: "flag", type: { kind: "bool" }, doc: "A field." },
        { name: "count", type: { kind: "int" }, doc: "" },
        { name: "ratio", type: { kind: "float" }, doc: "" },
        {
          name: "label",
          type: { kind: "nullable", element: { kind: "string" } },
          doc: "",
        },
        { name: "extra", type: { kind: "object" }, doc: "" },
        {
          name: "list",
          type: {
            kind: "array",
            element: { kind: "nullable", element: { kind: "string" } },
          },
          doc: "",
        },
        {
          name: "map",
          type: { kind: "map", element: { kind: "named", name: "Thing" } },
          doc: "",
        },
        {
          name: "mode",
          type: { kind: "enum", values: ["on", "off"] },
          doc: "",
        },
        {
          name: "inner",
          type: {
            kind: "struct",
            fields: [{ name: "x", type: { kind: "int" }, doc: "" }],
          },
          doc: "",
        },
      ],
    });
    assert.deepEqual(schema.methods.get("Get"), {
      name: "Get",
      input: {
        kind: "struct",
        fields: [{ name: "id", type: { kind: "string" }, doc: "" }],
      },
      output: {
        kind: "struct",
        fields: [
          { name: "thing", type: { kind: "named", name: "Thing" }, doc: "" },
        ],
      },
      doc: "",
    });
    assert.equal(
      schema.errors.get("Missing")?.doc,
      "Two lines\nof documentation.",
    );
  });

  it("drops comments separated by a blank line", () => {
    const schema = parse(`interface a.b

# Not about the method.

method M() -> ()
`);
    assert.equal(schema.methods.get("M")?.doc, "");
  });

  it("reports where it fails", () => {
    const fails = (source: string, message: string) =>
      assert.throws(() => parse(source), {
        name: IdlError.name,
        message,
      });

    fails("type T ()", '1:1: expected "interface", found "type"');
    fails("interface a.b\nmethod m() -> ()", '2:8: invalid member name "m"');
    fails("interface a.b\ntype T (x: ??int)", '2:13: invalid type "?"');
    fails("interface a.b\ntype T (x: U)", 'T.x: unknown type "U"');
    fails("interface a.b\ntype T ()\nerror T ()", '3:7: "T" is defined twice');
    fails("interface a.b\nmethod M() -> (a, b)", "2:15: expected a struct");
    fails(
      "interface a.b\ntype T (x: int",
      "end of input: unexpected end of input",
    );
    fails("interface a.b\ntype T (x: int;)", "2:15: unexpected character");
  });
});
