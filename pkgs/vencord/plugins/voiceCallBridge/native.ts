import { join } from "node:path";
import { Bridge, type Command } from "./bridge.ts";
import type { State } from "./io.siku2.VoiceCall.varlink.ts";

// Vencord loads this module whether or not the plugin is enabled, so nothing
// happens until the renderer calls start. The first parameter of every export
// is the IPC event, which is not needed here.

let bridge: Promise<Bridge> | undefined;

function socketPath(): string {
  const runtime = process.env.XDG_RUNTIME_DIR;
  if (!runtime) throw new Error("XDG_RUNTIME_DIR is not set");
  return join(runtime, "io.siku2.VoiceCall");
}

const onError = (error: unknown) => console.error("[VoiceCallBridge]", error);

/** Reloading the Discord window calls this again and keeps the server. */
export async function start(_: unknown): Promise<void> {
  bridge ??= Bridge.start(socketPath(), onError).catch((error: unknown) => {
    bridge = undefined;
    throw error;
  });
  await bridge;
}

export async function stop(_: unknown): Promise<void> {
  const running = bridge;
  bridge = undefined;
  await (await running)?.close();
}

export async function publish(_: unknown, state: State): Promise<void> {
  (await bridge)?.feed.set(state);
}

export async function nextCommand(_: unknown): Promise<Command> {
  const running = await bridge;
  if (running === undefined) throw new Error("the bridge is not running");
  return running.commands.next();
}
