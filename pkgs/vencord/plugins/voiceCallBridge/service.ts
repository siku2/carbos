import type { Interface } from "@carbos/varlink";
import type { Feed } from "./feed.ts";
import { errors, implement, type State } from "./io.siku2.VoiceCall.varlink.ts";

/** What the chat client has to do on request. Already being in the requested state is fine. */
export interface Commands {
  setMute(muted: boolean): Promise<void>;
  setDeafen(deafened: boolean): Promise<void>;
  leaveCall(): Promise<void>;
}

export function voiceCall(feed: Feed<State>, commands: Commands): Interface {
  return implement({
    Watch: async function* (_input, { signal }) {
      for await (const state of feed.watch(signal)) yield { state };
      throw new Error("the feed ended");
    },
    SetMute: async ({ muted }) => {
      await commands.setMute(muted);
      return {};
    },
    SetDeafen: async ({ deafened }) => {
      await commands.setDeafen(deafened);
      return {};
    },
    LeaveCall: async ({ id }) => {
      const call = feed.value?.call;
      if (!call || (id != null && id !== call.id)) throw errors.NotInCall();
      await commands.leaveCall();
      return {};
    },
  });
}
