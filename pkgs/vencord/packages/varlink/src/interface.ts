import { invalidParameter } from "./errors.ts";

export type Parameters = Record<string, unknown>;

export interface Context {
  /** Aborted when the client disconnects or the server closes. */
  readonly signal: AbortSignal;
}

export type Method =
  | {
      readonly kind: "call";
      readonly run: (
        parameters: Parameters,
        context: Context,
      ) => Promise<object>;
    }
  | {
      readonly kind: "stream";
      readonly run: (
        parameters: Parameters,
        context: Context,
      ) => AsyncGenerator<object, object, undefined>;
    };

export interface Interface {
  readonly name: string;
  readonly description: string;
  readonly methods: ReadonlyMap<string, Method>;
}

export function call<I, O extends object>(
  parse: (parameters: Parameters) => I,
  handler: (input: I, context: Context) => O | Promise<O>,
): Method {
  return {
    kind: "call",
    run: async (parameters, context) => handler(parse(parameters), context),
  };
}

/**
 * Every yield is a reply and the return value is the last one. Without "more",
 * the first yield is the only reply. Pending awaits should honor the signal.
 */
export function stream<I, O extends object>(
  parse: (parameters: Parameters) => I,
  handler: (input: I, context: Context) => AsyncGenerator<O, O, undefined>,
): Method {
  return {
    kind: "stream",
    run: (parameters, context) => handler(parse(parameters), context),
  };
}

/** Fails at startup if the description and the handlers disagree. */
export function defineInterface(
  description: string,
  methods: Record<string, Method>,
): Interface {
  const name = /^interface\s+([\w.]+)/m.exec(description)?.[1];
  if (name === undefined) {
    throw new Error("the description has no interface line");
  }

  const declared = new Set<string>();
  for (const match of description.matchAll(/^method\s+(\w+)/gm)) {
    if (match[1] !== undefined) declared.add(match[1]);
  }
  const implemented = new Set(Object.keys(methods));
  const missing = [...declared.difference(implemented)];
  const extra = [...implemented.difference(declared)];
  if (missing.length > 0 || extra.length > 0) {
    throw new Error(
      `${name}: not implemented [${missing.join(", ")}], not declared [${extra.join(", ")}]`,
    );
  }

  return { name, description, methods: new Map(Object.entries(methods)) };
}

export function boolean(parameters: Parameters, name: string): boolean {
  const value = parameters[name];
  if (typeof value !== "boolean") throw invalidParameter(name);
  return value;
}

export function string(parameters: Parameters, name: string): string {
  const value = parameters[name];
  if (typeof value !== "string") throw invalidParameter(name);
  return value;
}
