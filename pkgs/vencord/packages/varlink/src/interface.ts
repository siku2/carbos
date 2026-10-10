import { parse, type Schema } from "./idl.ts";

export interface Context {
  /** Aborted when the client disconnects or the server closes. */
  readonly signal: AbortSignal;
}

/**
 * Returns the reply, or yields one reply per update and returns the last. Without
 * "more", the first yield is the only reply. Pending awaits should honor the signal.
 */
export type Handler<I, O> = (
  input: I,
  context: Context,
) => O | Promise<O> | AsyncGenerator<O, O, undefined>;

export type AnyHandler = Handler<never, object>;

/** The parameters of a varlink "()". */
export type Empty = Readonly<Record<string, never>>;

export interface Interface {
  readonly schema: Schema;
  readonly description: string;
  readonly handlers: ReadonlyMap<string, AnyHandler>;
}

/** Fails at startup if the description and the handlers disagree. */
export function defineInterface(
  description: string,
  handlers: Readonly<Record<string, AnyHandler>>,
): Interface {
  const schema = parse(description);
  const declared = new Set(schema.methods.keys());
  const implemented = new Set(Object.keys(handlers));
  const missing = [...declared.difference(implemented)];
  const extra = [...implemented.difference(declared)];
  if (missing.length > 0 || extra.length > 0) {
    throw new Error(
      `${schema.name}: not implemented [${missing.join(", ")}], not declared [${extra.join(", ")}]`,
    );
  }
  return { schema, description, handlers: new Map(Object.entries(handlers)) };
}
