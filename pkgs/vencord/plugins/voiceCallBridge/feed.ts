/**
 * The latest value of something, for any number of watchers. The first change
 * goes out at once, later ones at most once per interval with the newest value.
 */
export class Feed<T> {
  readonly #interval: number;
  #latest: { value: T; json: string } | undefined;
  #published: { value: T; json: string } | undefined;
  #changed = Promise.withResolvers<void>();
  #cooldown: ReturnType<typeof setTimeout> | undefined;

  constructor(interval: number) {
    this.#interval = interval;
  }

  /** The newest value, even if watchers have not been told yet. */
  get value(): T | undefined {
    return this.#latest?.value;
  }

  set(value: T): void {
    const json = JSON.stringify(value);
    if (json === this.#latest?.json) return;
    this.#latest = { value, json };
    if (this.#cooldown === undefined) this.#publish();
  }

  /** Yields the current value, then every change, until the signal aborts. */
  async *watch(signal: AbortSignal): AsyncGenerator<T, never, undefined> {
    for (let seen: unknown; ; ) {
      const published = this.#published;
      if (published !== undefined && published !== seen) {
        seen = published;
        yield published.value;
      } else {
        await untilResolvedOrAborted(this.#changed.promise, signal);
      }
    }
  }

  #publish(): void {
    if (
      this.#latest === undefined ||
      this.#latest.json === this.#published?.json
    )
      return;
    this.#published = this.#latest;
    this.#changed.resolve();
    this.#changed = Promise.withResolvers();
    this.#cooldown = setTimeout(() => {
      this.#cooldown = undefined;
      this.#publish();
    }, this.#interval);
  }
}

function untilResolvedOrAborted(
  promise: Promise<void>,
  signal: AbortSignal,
): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal.aborted) {
      reject(signal.reason);
      return;
    }
    const abort = () => reject(signal.reason);
    signal.addEventListener("abort", abort, { once: true });
    void promise.then(() => {
      signal.removeEventListener("abort", abort);
      resolve();
    });
  });
}
