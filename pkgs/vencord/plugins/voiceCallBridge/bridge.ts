import { VarlinkServer } from "@carbos/varlink";
import { Feed } from "./feed.ts";
import type { State } from "./io.siku2.VoiceCall.varlink.ts";
import { type Commands, voiceCall } from "./service.ts";

export type Command =
  | { readonly kind: "setMute"; readonly muted: boolean }
  | { readonly kind: "setDeafen"; readonly deafened: boolean }
  | { readonly kind: "leaveCall" };

// Commands nobody fetches are stale soon, so only a few are kept.
const maxQueued = 16;

/** Hands commands to whoever fetches them. Delivery is all a command waits for. */
export class CommandQueue implements Commands {
  #queued: Command[] = [];
  #waiting: PromiseWithResolvers<Command> | undefined;

  setMute(muted: boolean): Promise<void> {
    return this.#push({ kind: "setMute", muted });
  }

  setDeafen(deafened: boolean): Promise<void> {
    return this.#push({ kind: "setDeafen", deafened });
  }

  leaveCall(): Promise<void> {
    return this.#push({ kind: "leaveCall" });
  }

  /** Only one caller waits at a time. A new call replaces the previous one. */
  next(): Promise<Command> {
    const queued = this.#queued.shift();
    if (queued !== undefined) return Promise.resolve(queued);
    this.#waiting = Promise.withResolvers();
    return this.#waiting.promise;
  }

  close(): void {
    this.#waiting?.reject(new Error("the bridge closed"));
    this.#waiting = undefined;
    this.#queued = [];
  }

  async #push(command: Command): Promise<void> {
    if (this.#waiting !== undefined) {
      this.#waiting.resolve(command);
      this.#waiting = undefined;
      return;
    }
    this.#queued.push(command);
    this.#queued.splice(0, this.#queued.length - maxQueued);
  }
}

export class Bridge {
  readonly feed = new Feed<State>(50);
  readonly commands = new CommandQueue();
  readonly #server: VarlinkServer;

  private constructor(onError: (error: unknown) => void) {
    this.#server = new VarlinkServer({
      info: {
        vendor: "carbos",
        product: "VoiceCallBridge",
        version: "1",
        url: "https://github.com/siku2/carbos",
      },
      interfaces: [voiceCall(this.feed, this.commands)],
      onError,
    });
  }

  static async start(
    path: string,
    onError: (error: unknown) => void,
  ): Promise<Bridge> {
    const bridge = new Bridge(onError);
    await bridge.#server.listen(path);
    return bridge;
  }

  async close(): Promise<void> {
    this.commands.close();
    await this.#server.close();
  }
}
