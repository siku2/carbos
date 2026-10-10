import { lstat, unlink } from "node:fs/promises";
import {
  createConnection,
  createServer,
  type Server,
  type Socket,
} from "node:net";
import {
  interfaceNotFound,
  invalidParameter,
  methodNotFound,
  VarlinkError,
} from "./errors.ts";
import type { MethodDefinition } from "./idl.ts";
import type { AnyHandler, Interface } from "./interface.ts";
import { encode, MessageReader, parseRequest, type Reply } from "./protocol.ts";
import { type ServerInfo, serviceInterface } from "./service.ts";
import { invalidField } from "./validate.ts";

export interface ServerOptions {
  readonly info: ServerInfo;
  readonly interfaces: Iterable<Interface>;
  /** Failures that are not the client's fault. The connection is dropped. */
  readonly onError?: (error: unknown) => void;
}

// A client that stops reading must not make the buffer grow without bound.
const maxBufferedBytes = 1 << 20;

export class VarlinkServer {
  readonly #interfaces = new Map<string, Interface>();
  readonly #onError: (error: unknown) => void;
  readonly #server: Server;
  readonly #connections = new Set<Socket>();
  readonly #closing = new AbortController();

  constructor(options: ServerOptions) {
    const service = serviceInterface(options.info, () =>
      this.#interfaces.values(),
    );
    for (const entry of [service, ...options.interfaces]) {
      this.#interfaces.set(entry.schema.name, entry);
    }
    this.#onError = options.onError ?? console.error;
    this.#server = createServer((socket) => this.#accept(socket));
  }

  /** Takes over a socket file left behind by a crash, but not a live one. */
  async listen(path: string): Promise<void> {
    try {
      await this.#bind(path);
    } catch (error) {
      if (!isErrno(error, "EADDRINUSE") || !(await isStale(path))) throw error;
      await unlink(path);
      await this.#bind(path);
    }
    this.#server.on("error", this.#onError);
  }

  async close(): Promise<void> {
    this.#closing.abort();
    for (const socket of this.#connections) socket.destroy();
    await new Promise<void>((resolve, reject) => {
      this.#server.close((error) => (error ? reject(error) : resolve()));
    });
  }

  #bind(path: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this.#server.once("error", reject);
      this.#server.listen(path, () => {
        this.#server.off("error", reject);
        resolve();
      });
    });
  }

  #accept(socket: Socket): void {
    this.#connections.add(socket);
    const disconnected = new AbortController();
    const signal = AbortSignal.any([disconnected.signal, this.#closing.signal]);
    const reader = new MessageReader();
    const queue: unknown[] = [];
    let busy = false;

    // Requests on one connection are answered in order, one at a time.
    const drain = async () => {
      if (busy) return;
      busy = true;
      try {
        for (
          let next = queue.shift();
          next !== undefined && !signal.aborted;
          next = queue.shift()
        ) {
          await this.#dispatch(next, socket, signal);
        }
      } catch (error) {
        this.#onError(error);
        socket.destroy();
      } finally {
        busy = false;
      }
    };

    socket.on("data", (chunk: Buffer) => {
      try {
        queue.push(...reader.push(chunk));
      } catch (error) {
        this.#onError(error);
        socket.destroy();
        return;
      }
      void drain();
    });
    // The close event follows and does the cleanup.
    socket.on("error", () => {});
    socket.on("close", () => {
      disconnected.abort();
      this.#connections.delete(socket);
    });
  }

  async #dispatch(
    message: unknown,
    socket: Socket,
    signal: AbortSignal,
  ): Promise<void> {
    const request = parseRequest(message);
    const send = (reply: Reply) => {
      if (request.oneway || socket.destroyed) return;
      socket.write(encode(reply));
      if (socket.writableLength > maxBufferedBytes) socket.destroy();
    };

    try {
      if (request.upgrade) throw invalidParameter("upgrade");
      const { entry, definition, handler } = this.#resolve(request.method);
      const invalid = invalidField(
        entry.schema,
        definition.input,
        request.parameters,
      );
      if (invalid !== undefined) throw invalidParameter(invalid);

      // Replies that break the schema are bugs, not the client's fault.
      const checked = (output: object): object => {
        const field = invalidField(
          entry.schema,
          definition.output,
          output as Record<string, unknown>,
        );
        if (field !== undefined) {
          throw new Error(
            `${request.method} replied with an invalid "${field}"`,
          );
        }
        return output;
      };

      // The parameters match the schema the handler's types come from.
      const result = handler(request.parameters as never, { signal });
      if (!isAsyncGenerator(result)) {
        send({ parameters: checked(await result) });
        return;
      }

      try {
        for (
          let next = await result.next();
          !signal.aborted;
          next = await result.next()
        ) {
          if (next.done || !request.more) {
            send({ parameters: checked(next.value) });
            return;
          }
          send({ parameters: checked(next.value), continues: true });
        }
      } finally {
        await result.return({});
      }
    } catch (error) {
      if (signal.aborted) return;
      if (!(error instanceof VarlinkError)) throw error;
      this.#checkError(error);
      send({ error: error.error, parameters: error.parameters });
    }
  }

  #resolve(qualified: string): {
    entry: Interface;
    definition: MethodDefinition;
    handler: AnyHandler;
  } {
    const dot = qualified.lastIndexOf(".");
    const name = qualified.slice(0, Math.max(dot, 0));
    const entry = this.#interfaces.get(name);
    if (entry === undefined) throw interfaceNotFound(name);
    const method = qualified.slice(dot + 1);
    const definition = entry.schema.methods.get(method);
    const handler = entry.handlers.get(method);
    if (definition === undefined || handler === undefined) {
      throw methodNotFound(qualified);
    }
    return { entry, definition, handler };
  }

  #checkError({ error, parameters }: VarlinkError): void {
    const dot = error.lastIndexOf(".");
    const entry = this.#interfaces.get(error.slice(0, dot));
    const definition = entry?.schema.errors.get(error.slice(dot + 1));
    if (entry === undefined || definition === undefined) return;
    const field = invalidField(entry.schema, definition.parameters, parameters);
    if (field !== undefined) {
      throw new Error(`${error} has an invalid "${field}"`);
    }
  }
}

const isAsyncGenerator = (
  value: unknown,
): value is AsyncGenerator<object, object, undefined> =>
  typeof value === "object" && value !== null && Symbol.asyncIterator in value;

const isErrno = (error: unknown, code: string) =>
  error instanceof Error && "code" in error && error.code === code;

async function isStale(path: string): Promise<boolean> {
  if (!(await lstat(path)).isSocket()) return false;
  return new Promise((resolve) => {
    const probe = createConnection(path);
    probe.once("connect", () => {
      probe.destroy();
      resolve(false);
    });
    probe.once("error", () => resolve(true));
  });
}
