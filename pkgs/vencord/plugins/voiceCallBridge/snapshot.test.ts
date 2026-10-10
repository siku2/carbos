import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  type Channel,
  type Discord,
  snapshot,
  type User,
  type VoiceState,
} from "./snapshot.ts";

const user = (id: string, username: string, globalName?: string): User => ({
  id,
  username,
  globalName,
  avatarUrl: (guildId, size) =>
    `https://cdn/${guildId ?? "-"}/${id}?size=${size}`,
});

const voice = (
  userId: string,
  flags: Partial<VoiceState> = {},
): VoiceState => ({
  userId,
  selfMute: false,
  selfDeaf: false,
  mute: false,
  deaf: false,
  suppress: false,
  ...flags,
});

function fake(overrides: Partial<Discord> = {}): Discord {
  const users = new Map([
    ["1", user("1", "me")],
    ["2", user("2", "zoe", "Zoe")],
    ["3", user("3", "adam")],
  ]);
  const channels = new Map<string, Channel>([
    ["c", { id: "c", name: "General", guildId: "g", recipientIds: [] }],
    ["dm", { id: "dm", name: "", guildId: null, recipientIds: ["2", "3"] }],
  ]);
  return {
    selfId: () => "1",
    selfMuted: () => false,
    selfDeafened: () => false,
    voiceChannelId: () => "c",
    channel: (id) => channels.get(id),
    guildName: () => "Home",
    voiceStates: () => [voice("1"), voice("2"), voice("3")],
    user: (id) => users.get(id),
    nick: (_, userId) => (userId === "3" ? "Bob" : undefined),
    speaking: (userId) => userId === "2",
    locallyMuted: () => false,
    ...overrides,
  };
}

describe("snapshot", () => {
  it("is empty outside a call", () => {
    assert.deepEqual(snapshot(fake({ voiceChannelId: () => null })), {
      muted: false,
      deafened: false,
      call: null,
    });
  });

  it("describes the call and its participants", () => {
    const { call } = snapshot(fake());
    assert.equal(call?.id, "c");
    assert.equal(call?.name, "General");
    assert.equal(call?.server, "Home");
    assert.deepEqual(
      call?.participants.map(({ name, speaking, self }) => ({
        name,
        speaking,
        self,
      })),
      [
        { name: "Bob", speaking: false, self: false },
        { name: "me", speaking: false, self: true },
        { name: "Zoe", speaking: true, self: false },
      ],
    );
  });

  it("offers the server avatar in several sizes", () => {
    const me = snapshot(fake()).call?.participants.find(({ self }) => self);
    assert.deepEqual(
      me?.avatar.map(({ url, width, height }) => [url, width, height]),
      [
        ["https://cdn/g/1?size=32", 32, 32],
        ["https://cdn/g/1?size=64", 64, 64],
        ["https://cdn/g/1?size=128", 128, 128],
        ["https://cdn/g/1?size=256", 256, 256],
      ],
    );
  });

  it("tells apart who muted whom", () => {
    const participants =
      snapshot(
        fake({
          voiceStates: () => [
            voice("1", { selfMute: true, selfDeaf: true }),
            voice("2", { mute: true, deaf: true }),
            voice("3", { suppress: true }),
          ],
          locallyMuted: () => true,
        }),
      ).call?.participants ?? [];
    const flags = Object.fromEntries(
      participants.map((p) => [
        p.id,
        [
          p.selfMuted,
          p.selfDeafened,
          p.serverMuted,
          p.serverDeafened,
          p.locallyMuted,
        ],
      ]),
    );
    assert.deepEqual(flags, {
      "1": [true, true, false, false, false],
      "2": [false, false, true, true, true],
      "3": [false, false, true, false, true],
    });
  });

  it("names direct calls after the other people", () => {
    const { call } = snapshot(
      fake({ voiceChannelId: () => "dm", voiceStates: () => [] }),
    );
    assert.equal(call?.name, "Zoe, adam");
    assert.equal(call?.server, null);
  });

  it("reports the local toggles", () => {
    const state = snapshot(
      fake({ selfMuted: () => true, selfDeafened: () => true }),
    );
    assert.equal(state.muted, true);
    assert.equal(state.deafened, true);
  });
});
