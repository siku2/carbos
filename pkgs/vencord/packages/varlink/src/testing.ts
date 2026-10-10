import { mkdtemp, rm } from "node:fs/promises";
import { createConnection, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { encode, MessageReader } from "./protocol.ts";

/** A raw client, so tests can do what well-behaved clients never would. */
export class TestClient {
  readonly #socket: Socket;
  readonly #replies: unknown[] = [];
  readonly #waiting: ((reply: unknown) => void)[] = [];
  readonly closed: Promise<void>;

  private constructor(socket: Socket) {
    this.#socket = socket;
    const reader = new MessageReader();
    socket.on("data", (chunk: Buffer) => {
      for (const reply of reader.push(chunk)) {
        const waiter = this.#waiting.shift();
        if (waiter === undefined) this.#replies.push(reply);
        else waiter(reply);
      }
    });
    this.closed = new Promise((resolve) =>
      socket.once("close", () => resolve()),
    );
  }

  static connect(path: string): Promise<TestClient> {
    return new Promise((resolve, reject) => {
      const socket = createConnection(path);
      socket.once("connect", () => resolve(new TestClient(socket)));
      socket.once("error", reject);
    });
  }

  send(request: object): void {
    this.write(encode(request));
  }

  write(bytes: Buffer): void {
    this.#socket.write(bytes);
  }

  reply(): Promise<unknown> {
    if (this.#replies.length > 0) return Promise.resolve(this.#replies.shift());
    return new Promise((resolve) => this.#waiting.push(resolve));
  }

  async call(request: object): Promise<unknown> {
    this.send(request);
    return this.reply();
  }

  close(): void {
    this.#socket.destroy();
  }
}

export async function tempSocket(): Promise<{
  path: string;
  [Symbol.asyncDispose](): Promise<void>;
}> {
  const dir = await mkdtemp(join(tmpdir(), "varlink-"));
  return {
    path: join(dir, "socket"),
    [Symbol.asyncDispose]: () => rm(dir, { recursive: true, force: true }),
  };
}

export function untilAborted(signal: AbortSignal): Promise<never> {
  return new Promise((_, reject) => {
    if (signal.aborted) reject(signal.reason);
    signal.addEventListener("abort", () => reject(signal.reason), {
      once: true,
    });
  });
}
