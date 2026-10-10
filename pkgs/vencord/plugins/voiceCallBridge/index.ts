import { Logger } from "@utils/Logger";
import definePlugin, { type PluginNative } from "@utils/types";
import type { Command } from "./bridge.ts";

const Native = VencordNative.pluginHelpers.VoiceCallBridge as PluginNative<
  typeof import("./native.ts")
>;

const logger = new Logger("VoiceCallBridge");

let running = false;

async function runCommands(): Promise<void> {
  while (running) {
    let command: Command;
    try {
      command = await Native.nextCommand();
    } catch (error) {
      if (running) logger.error("Lost the command channel", error);
      return;
    }
    logger.warn("Commands are not implemented yet", command);
  }
}

export default definePlugin({
  name: "VoiceCallBridge",
  description: "Publishes the current voice call over varlink.",
  authors: [{ name: "siku2", id: 0n }],

  start() {
    running = true;
    Native.start().then(runCommands, (error: unknown) => {
      logger.error("Could not start the varlink server", error);
    });
  },

  stop() {
    running = false;
    Native.stop().catch((error: unknown) => {
      logger.error("Could not stop the varlink server", error);
    });
  },
});
