export interface Request {
  readonly method: string;
  readonly parameters: Record<string, unknown>;
  readonly oneway: boolean;
  readonly more: boolean;
  readonly upgrade: boolean;
}

export interface Reply {
  readonly parameters?: object;
  readonly continues?: boolean;
  readonly error?: string;
}

export class ProtocolError extends Error {
  override readonly name = "ProtocolError";
}

export const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export function parseRequest(message: unknown): Request {
  if (!isRecord(message) || typeof message.method !== "string") {
    throw new ProtocolError("request without a method");
  }
  const {
    parameters = {},
    oneway = false,
    more = false,
    upgrade = false,
  } = message;
  if (
    !isRecord(parameters) ||
    typeof oneway !== "boolean" ||
    typeof more !== "boolean" ||
    typeof upgrade !== "boolean"
  ) {
    throw new ProtocolError(`malformed request for ${message.method}`);
  }
  return { method: message.method, parameters, oneway, more, upgrade };
}

/** Splits a byte stream into NUL-terminated JSON messages. */
export class MessageReader {
  #buffered: Buffer = Buffer.alloc(0);

  push(chunk: Buffer): unknown[] {
    const messages: unknown[] = [];
    let data =
      this.#buffered.length > 0
        ? Buffer.concat([this.#buffered, chunk])
        : chunk;
    for (let end = data.indexOf(0); end !== -1; end = data.indexOf(0)) {
      messages.push(JSON.parse(data.subarray(0, end).toString("utf8")));
      data = data.subarray(end + 1);
    }
    this.#buffered = data;
    return messages;
  }
}

export const encode = (message: object): Buffer =>
  Buffer.from(`${JSON.stringify(message)}\0`, "utf8");
