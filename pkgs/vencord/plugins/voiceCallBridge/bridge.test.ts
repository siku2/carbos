import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { TestClient, tempSocket } from "@carbos/varlink/testing";
import { Bridge, CommandQueue } from "./bridge.ts";
import type { State } from "./io.siku2.VoiceCall.varlink.ts";

describe("CommandQueue", () => {
  it("hands a command to a waiting caller", async () => {
    const queue = new CommandQueue();
    const next = queue.next();
    await queue.setMute(true);
    assert.deepEqual(await next, { kind: "setMute", muted: true });
  });

  it("keeps commands until someone asks, but only a few", async () => {
    const queue = new CommandQueue();
    for (let i = 0; i < 20; i++) await queue.setMute(i % 2 === 0);
    await queue.leaveCall();
    const commands = [];
    for (let i = 0; i < 16; i++) commands.push(await queue.next());
    assert.deepEqual(commands.at(-1), { kind: "leaveCall" });
    assert.deepEqual(commands[0], { kind: "setMute", muted: false });
  });

  it("rejects a waiting caller on close", async () => {
    const queue = new CommandQueue();
    const next = queue.next();
    queue.close();
    await assert.rejects(next, { message: "the bridge closed" });
  });
});

describe("Bridge", () => {
  it("serves published state and passes commands on", async () => {
    await using socket = await tempSocket();
    const errors: unknown[] = [];
    const bridge = await Bridge.start(socket.path, (error) =>
      errors.push(error),
    );
    const state: State = { muted: false, deafened: false, call: null };
    bridge.feed.set(state);

    const client = await TestClient.connect(socket.path);
    assert.deepEqual(
      await client.call({ method: "io.siku2.VoiceCall.Watch" }),
      {
        parameters: { state },
      },
    );
    const command = bridge.commands.next();
    assert.deepEqual(
      await client.call({
        method: "io.siku2.VoiceCall.SetDeafen",
        parameters: { deafened: true },
      }),
      { parameters: {} },
    );
    assert.deepEqual(await command, { kind: "setDeafen", deafened: true });

    client.close();
    await bridge.close();
    assert.deepEqual(errors, []);
  });

  it("reports invalid state instead of serving it", async () => {
    await using socket = await tempSocket();
    const errors: unknown[] = [];
    const bridge = await Bridge.start(socket.path, (error) =>
      errors.push(error),
    );
    bridge.feed.set({ muted: "no" } as unknown as State);

    const client = await TestClient.connect(socket.path);
    client.send({ method: "io.siku2.VoiceCall.Watch" });
    await client.closed;
    assert.equal(errors.length, 1);
    await bridge.close();
  });
});
