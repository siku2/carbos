import assert from "node:assert/strict";
import { afterEach, beforeEach, describe, it, mock } from "node:test";
import { setImmediate } from "node:timers/promises";
import { Feed } from "./feed.ts";

/** Lets pending promises settle, then tells whether this one did. */
async function settled(promise: Promise<unknown>): Promise<boolean> {
  let done = false;
  void promise.then(
    () => {
      done = true;
    },
    () => {
      done = true;
    },
  );
  for (let i = 0; i < 10; i++) await setImmediate();
  return done;
}

describe("Feed", () => {
  beforeEach(() => mock.timers.enable({ apis: ["setTimeout"] }));
  afterEach(() => mock.timers.reset());

  it("waits for the first value", async () => {
    const feed = new Feed<number>(50);
    const watch = feed.watch(new AbortController().signal);
    const first = watch.next();
    assert.equal(await settled(first), false);
    feed.set(1);
    assert.deepEqual(await first, { done: false, value: 1 });
  });

  it("ignores values equal to the current one", async () => {
    const feed = new Feed<{ n: number }>(50);
    feed.set({ n: 1 });
    const watch = feed.watch(new AbortController().signal);
    await watch.next();
    mock.timers.tick(50);
    feed.set({ n: 1 });
    assert.equal(await settled(watch.next()), false);
  });

  it("sends the first change at once and coalesces the rest", async () => {
    const feed = new Feed<number>(50);
    feed.set(1);
    const watch = feed.watch(new AbortController().signal);
    await watch.next();

    mock.timers.tick(50);
    feed.set(2);
    assert.deepEqual(await watch.next(), { done: false, value: 2 });

    feed.set(3);
    feed.set(4);
    const next = watch.next();
    assert.equal(await settled(next), false);
    assert.equal(feed.value, 4);
    mock.timers.tick(50);
    assert.deepEqual(await next, { done: false, value: 4 });
  });

  it("sends nothing for a change that is undone within the interval", async () => {
    const feed = new Feed<number>(50);
    feed.set(1);
    const watch = feed.watch(new AbortController().signal);
    await watch.next();
    feed.set(2);
    feed.set(1);
    mock.timers.tick(50);
    assert.equal(await settled(watch.next()), false);
  });

  it("serves several watchers", async () => {
    const feed = new Feed<number>(50);
    const signal = new AbortController().signal;
    const a = feed.watch(signal);
    const b = feed.watch(signal);
    const next = Promise.all([a.next(), b.next()]);
    feed.set(1);
    assert.deepEqual(
      (await next).map(({ value }) => value),
      [1, 1],
    );
  });

  it("stops when the signal aborts", async () => {
    const feed = new Feed<number>(50);
    const abort = new AbortController();
    const next = feed.watch(abort.signal).next();
    abort.abort(new Error("gone"));
    await assert.rejects(next, { message: "gone" });
  });
});
