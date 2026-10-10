import { Logger } from "@utils/Logger";
import definePlugin, { type PluginNative } from "@utils/types";
import type { Command } from "./bridge.ts";
import { discord, run, sources } from "./discord.ts";
import { snapshot } from "./snapshot.ts";

const Native = VencordNative.pluginHelpers.VoiceCallBridge as PluginNative<
  typeof import("./native.ts")
>;

const logger = new Logger("VoiceCallBridge");

// The stores change many times per second during a call, mostly in ways the
// state does not show. Changes are batched and only new states are sent.
const batchInterval = 25;

let running = false;
let batch: ReturnType<typeof setTimeout> | undefined;
let lastSent: string | undefined;

function publish(): void {
  batch = undefined;
  try {
    const state = snapshot(discord);
    const json = JSON.stringify(state);
    if (json === lastSent) return;
    lastSent = json;
    Native.publish(state).catch((error: unknown) => {
      logger.error("Could not publish the state", error);
    });
  } catch (error) {
    logger.error("Could not read the voice state", error);
  }
}

function schedule(): void {
  batch ??= setTimeout(publish, batchInterval);
}

async function runCommands(): Promise<void> {
  while (running) {
    let command: Command;
    try {
      command = await Native.nextCommand();
    } catch (error) {
      if (running) logger.error("Lost the command channel", error);
      return;
    }
    try {
      run(command);
    } catch (error) {
      logger.error("Could not run a command", command, error);
    }
  }
}

export default definePlugin({
  name: "VoiceCallBridge",
  description: "Publishes the current voice call over varlink.",
  authors: [{ name: "siku2", id: 0n }],

  start() {
    running = true;
    lastSent = undefined;
    Native.start().then(
      () => {
        for (const source of sources()) source.addChangeListener(schedule);
        publish();
        void runCommands();
      },
      (error: unknown) => {
        logger.error("Could not start the varlink server", error);
      },
    );
  },

  stop() {
    running = false;
    for (const source of sources()) source.removeChangeListener(schedule);
    clearTimeout(batch);
    batch = undefined;
    Native.stop().catch((error: unknown) => {
      logger.error("Could not stop the varlink server", error);
    });
  },
});
