import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  encode,
  MessageReader,
  ProtocolError,
  parseRequest,
} from "./protocol.ts";

describe("MessageReader", () => {
  it("joins messages split across chunks", () => {
    const reader = new MessageReader();
    const bytes = encode({ method: "a.B" });
    assert.deepEqual(reader.push(bytes.subarray(0, 5)), []);
    assert.deepEqual(reader.push(bytes.subarray(5)), [{ method: "a.B" }]);
  });

  it("splits several messages in one chunk", () => {
    const reader = new MessageReader();
    const bytes = Buffer.concat([
      encode({ n: 1 }),
      encode({ n: 2 }),
      encode({ n: 3 }).subarray(0, 3),
    ]);
    assert.deepEqual(reader.push(bytes), [{ n: 1 }, { n: 2 }]);
  });

  it("rejects invalid JSON", () => {
    assert.throws(
      () => new MessageReader().push(Buffer.from("{\0")),
      SyntaxError,
    );
  });
});

describe("parseRequest", () => {
  it("fills in the defaults", () => {
    assert.deepEqual(parseRequest({ method: "a.B" }), {
      method: "a.B",
      parameters: {},
      oneway: false,
      more: false,
      upgrade: false,
    });
  });

  it("rejects malformed requests", () => {
    assert.throws(() => parseRequest({}), ProtocolError);
    assert.throws(
      () => parseRequest({ method: "a.B", more: "yes" }),
      ProtocolError,
    );
    assert.throws(
      () => parseRequest({ method: "a.B", parameters: [] }),
      ProtocolError,
    );
  });
});
