import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { link, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:net";
import { describe, it } from "node:test";
import { promisify } from "node:util";
import { VarlinkError } from "./errors.ts";
import { call, defineInterface, stream, string } from "./interface.ts";
import { VarlinkServer } from "./server.ts";
import { TestClient, tempSocket, untilAborted } from "./testing.ts";

const info = {
  vendor: "carbos",
  product: "test",
  version: "0",
  url: "https://example.com",
};

const description = `interface io.test

method Echo(text: string) -> (text: string)
method Count(to: int) -> (n: int)
method Watch() -> (n: int)
method Fail() -> ()
method Crash() -> ()

error Failed (reason: string)
`;

function testServer() {
  const watch = { cleanedUp: Promise.withResolvers<void>() };
  const errors: unknown[] = [];
  const server = new VarlinkServer({
    info,
    onError: (error) => errors.push(error),
    interfaces: [
      defineInterface(description, {
        Echo: call(
          (parameters) => string(parameters, "text"),
          (text) => ({ text }),
        ),
        Count: stream(
          (parameters) => Number(parameters.to),
          async function* (to) {
            for (let n = 0; n < to; n++) yield { n };
            return { n: to };
          },
        ),
        Watch: stream(
          () => undefined,
          async function* (_, { signal }) {
            try {
              yield { n: 0 };
              return await untilAborted(signal);
            } finally {
              watch.cleanedUp.resolve();
            }
          },
        ),
        Fail: call(
          () => undefined,
          () => {
            throw new VarlinkError("io.test.Failed", { reason: "asked to" });
          },
        ),
        Crash: call(
          () => undefined,
          () => {
            throw new Error("bug");
          },
        ),
      }),
    ],
  });
  return { server, watch, errors };
}

async function serve() {
  const socket = await tempSocket();
  const { server, ...rest } = testServer();
  await server.listen(socket.path);
  return {
    ...rest,
    server,
    path: socket.path,
    async [Symbol.asyncDispose]() {
      await server.close();
      await socket[Symbol.asyncDispose]();
    },
  };
}

describe("VarlinkServer", () => {
  it("answers a call", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    assert.deepEqual(
      await client.call({ method: "io.test.Echo", parameters: { text: "hi" } }),
      {
        parameters: { text: "hi" },
      },
    );
    client.close();
  });

  it("reports unknown interfaces, methods and bad parameters", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    assert.deepEqual(await client.call({ method: "io.nope.Echo" }), {
      error: "org.varlink.service.InterfaceNotFound",
      parameters: { interface: "io.nope" },
    });
    assert.deepEqual(await client.call({ method: "io.test.Nope" }), {
      error: "org.varlink.service.MethodNotFound",
      parameters: { method: "io.test.Nope" },
    });
    assert.deepEqual(
      await client.call({ method: "io.test.Echo", parameters: { text: 1 } }),
      {
        error: "org.varlink.service.InvalidParameter",
        parameters: { parameter: "text" },
      },
    );
    client.close();
  });

  it("passes interface errors to the client", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    assert.deepEqual(await client.call({ method: "io.test.Fail" }), {
      error: "io.test.Failed",
      parameters: { reason: "asked to" },
    });
    client.close();
  });

  it("drops the connection on a handler bug and keeps serving", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    client.send({ method: "io.test.Crash" });
    await client.closed;
    assert.equal(s.errors.length, 1);

    const other = await TestClient.connect(s.path);
    assert.deepEqual(
      await other.call({
        method: "io.test.Echo",
        parameters: { text: "still here" },
      }),
      {
        parameters: { text: "still here" },
      },
    );
    other.close();
  });

  it("streams replies with more", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    client.send({ method: "io.test.Count", parameters: { to: 2 }, more: true });
    assert.deepEqual(await client.reply(), {
      parameters: { n: 0 },
      continues: true,
    });
    assert.deepEqual(await client.reply(), {
      parameters: { n: 1 },
      continues: true,
    });
    assert.deepEqual(await client.reply(), { parameters: { n: 2 } });
    client.close();
  });

  it("sends only the first reply without more and closes the stream", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    assert.deepEqual(await client.call({ method: "io.test.Watch" }), {
      parameters: { n: 0 },
    });
    await s.watch.cleanedUp.promise;
    client.close();
  });

  it("ends a stream when the client disconnects", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    assert.deepEqual(
      await client.call({ method: "io.test.Watch", more: true }),
      {
        parameters: { n: 0 },
        continues: true,
      },
    );
    client.close();
    await s.watch.cleanedUp.promise;
    assert.deepEqual(s.errors, []);
  });

  it("answers requests on one connection in order", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    client.send({ method: "io.test.Count", parameters: { to: 1 }, more: true });
    client.send({ method: "io.test.Echo", parameters: { text: "after" } });
    assert.deepEqual(await client.reply(), {
      parameters: { n: 0 },
      continues: true,
    });
    assert.deepEqual(await client.reply(), { parameters: { n: 1 } });
    assert.deepEqual(await client.reply(), { parameters: { text: "after" } });
    client.close();
  });

  it("does not reply to oneway calls", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    client.send({
      method: "io.test.Echo",
      parameters: { text: "ignored" },
      oneway: true,
    });
    assert.deepEqual(
      await client.call({
        method: "io.test.Echo",
        parameters: { text: "next" },
      }),
      {
        parameters: { text: "next" },
      },
    );
    client.close();
  });

  it("drops a client that sends invalid JSON", async () => {
    await using s = await serve();
    const client = await TestClient.connect(s.path);
    client.write(Buffer.from("not json\0"));
    await client.closed;
  });

  it("takes over a stale socket file", async () => {
    await using socket = await tempSocket();
    const old = createServer();
    await new Promise<void>((resolve) =>
      old.listen(`${socket.path}.old`, resolve),
    );
    await link(`${socket.path}.old`, socket.path);
    await new Promise<void>((resolve) => old.close(() => resolve()));

    const { server } = testServer();
    await server.listen(socket.path);
    await server.close();
  });

  it("leaves other files alone", async () => {
    await using socket = await tempSocket();
    await writeFile(socket.path, "keep");
    const { server } = testServer();
    await assert.rejects(server.listen(socket.path), { code: "EADDRINUSE" });
    assert.equal(await readFile(socket.path, "utf8"), "keep");
  });

  it("refuses a socket another server is using", async () => {
    await using s = await serve();
    const { server } = testServer();
    await assert.rejects(server.listen(s.path), { code: "EADDRINUSE" });
  });

  it("aborts running streams on close", async () => {
    const socket = await tempSocket();
    const { server, watch } = testServer();
    await server.listen(socket.path);
    const client = await TestClient.connect(socket.path);
    await client.call({ method: "io.test.Watch", more: true });
    await server.close();
    await watch.cleanedUp.promise;
    await client.closed;
    await socket[Symbol.asyncDispose]();
  });
});

describe("varlinkctl", () => {
  const varlinkctl = async (...args: string[]) =>
    (await promisify(execFile)("varlinkctl", ["--json=short", ...args])).stdout;

  it("introspects every interface", async () => {
    await using s = await serve();
    const { interfaces } = JSON.parse(await varlinkctl("info", s.path));
    assert.deepEqual(interfaces, ["org.varlink.service", "io.test"]);
    for (const name of interfaces) {
      await varlinkctl("introspect", s.path, name);
    }
  });

  it("calls and streams", async () => {
    await using s = await serve();
    assert.deepEqual(
      JSON.parse(
        await varlinkctl("call", s.path, "io.test.Echo", '{"text":"hi"}'),
      ),
      {
        text: "hi",
      },
    );
    // With --more, the output is a JSON text sequence (RFC 7464).
    const records = (
      await varlinkctl("call", "--more", s.path, "io.test.Count", '{"to":2}')
    )
      .split("\u001e")
      .filter((record) => record.trim() !== "");
    assert.deepEqual(
      records.map((record) => JSON.parse(record)),
      [{ n: 0 }, { n: 1 }, { n: 2 }],
    );
  });
});
