import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { describe, it } from "node:test";
import { promisify } from "node:util";
import { VarlinkServer } from "@carbos/varlink";
import { TestClient, tempSocket } from "@carbos/varlink/testing";
import { Feed } from "./feed.ts";
import type { Participant, State } from "./io.siku2.VoiceCall.varlink.ts";
import { voiceCall } from "./service.ts";

const self: Participant = {
  id: "1",
  name: "me",
  avatar: [{ url: "https://example.com/a.png", width: 64, height: 64 }],
  speaking: false,
  selfMuted: false,
  selfDeafened: false,
  serverMuted: false,
  serverDeafened: false,
  locallyMuted: false,
  self: true,
};

const inCall: State = {
  muted: false,
  deafened: false,
  call: { id: "c1", name: "General", server: "Home", participants: [self] },
};

async function serve(initial?: State) {
  const socket = await tempSocket();
  const feed = new Feed<State>(0);
  if (initial) feed.set(initial);
  const calls: string[] = [];
  const server = new VarlinkServer({
    info: { vendor: "", product: "", version: "", url: "" },
    interfaces: [
      voiceCall(feed, {
        setMute: async (muted) => void calls.push(`mute ${muted}`),
        setDeafen: async (deafened) => void calls.push(`deafen ${deafened}`),
        leaveCall: async () => void calls.push("leave"),
      }),
    ],
  });
  await server.listen(socket.path);
  return {
    path: socket.path,
    feed,
    calls,
    async [Symbol.asyncDispose]() {
      await server.close();
      await socket[Symbol.asyncDispose]();
    },
  };
}

const varlinkctl = async (...args: string[]) =>
  (await promisify(execFile)("varlinkctl", ["--json=short", ...args])).stdout;

describe("io.siku2.VoiceCall", () => {
  it("replies with the state the schema describes", async () => {
    await using s = await serve(inCall);
    const reply = await varlinkctl(
      "call",
      s.path,
      "io.siku2.VoiceCall.Watch",
      "{}",
    );
    assert.deepEqual(JSON.parse(reply), { state: inCall });
  });

  it("streams changes", async () => {
    await using s = await serve(inCall);
    const client = await TestClient.connect(s.path);
    client.send({ method: "io.siku2.VoiceCall.Watch", more: true });
    assert.deepEqual(await client.reply(), {
      parameters: { state: inCall },
      continues: true,
    });

    const left: State = { ...inCall, call: null };
    s.feed.set(left);
    assert.deepEqual(await client.reply(), {
      parameters: { state: left },
      continues: true,
    });
    client.close();
  });

  it("passes commands on", async () => {
    await using s = await serve(inCall);
    const call = (method: string, parameters: object) =>
      varlinkctl(
        "call",
        s.path,
        `io.siku2.VoiceCall.${method}`,
        JSON.stringify(parameters),
      );
    await call("SetMute", { muted: true });
    await call("SetDeafen", { deafened: false });
    await call("LeaveCall", { id: "c1" });
    await call("LeaveCall", {});
    assert.deepEqual(s.calls, ["mute true", "deafen false", "leave", "leave"]);
  });

  it("only leaves the given call", async () => {
    await using s = await serve(inCall);
    const client = await TestClient.connect(s.path);
    const notInCall = { error: "io.siku2.VoiceCall.NotInCall", parameters: {} };
    assert.deepEqual(
      await client.call({
        method: "io.siku2.VoiceCall.LeaveCall",
        parameters: { id: "c2" },
      }),
      notInCall,
    );
    s.feed.set({ ...inCall, call: null });
    assert.deepEqual(
      await client.call({ method: "io.siku2.VoiceCall.LeaveCall" }),
      notInCall,
    );
    assert.deepEqual(s.calls, []);
    client.close();
  });
});
