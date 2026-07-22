import { describe, expect, it } from "vitest";
import {
  IDLE_SEEK_STREAK,
  nextSeekStep,
  SEEK_ACCEL_WINDOW_MS,
  SEEK_PRESSES_PER_TIER,
  SEEK_TIER_STEPS_MS,
  SeekStreak,
} from "@/player/seekAcceleration";

function press(streak: SeekStreak, dir: -1 | 1, at: number) {
  return nextSeekStep(streak, dir, at);
}

describe("nextSeekStep", () => {
  it("starts at the base step", () => {
    const { deltaMs } = press(IDLE_SEEK_STREAK, 1, 1000);
    expect(deltaMs).toBe(SEEK_TIER_STEPS_MS[0]);
  });

  it("keeps the base step for slow deliberate taps", () => {
    let streak: SeekStreak = IDLE_SEEK_STREAK;
    let at = 1000;
    for (let i = 0; i < 20; i++) {
      const step = press(streak, 1, at);
      expect(step.deltaMs).toBe(SEEK_TIER_STEPS_MS[0]);
      streak = step.streak;
      at += SEEK_ACCEL_WINDOW_MS + 1;
    }
  });

  it("climbs a tier after enough rapid same-direction presses", () => {
    let streak: SeekStreak = IDLE_SEEK_STREAK;
    let at = 1000;
    const deltas: number[] = [];
    for (let i = 0; i < SEEK_PRESSES_PER_TIER + 1; i++) {
      const step = press(streak, 1, at);
      deltas.push(step.deltaMs);
      streak = step.streak;
      at += 100;
    }
    expect(deltas.slice(0, SEEK_PRESSES_PER_TIER)).toEqual(
      Array(SEEK_PRESSES_PER_TIER).fill(SEEK_TIER_STEPS_MS[0]),
    );
    expect(deltas[SEEK_PRESSES_PER_TIER]).toBe(SEEK_TIER_STEPS_MS[1]);
  });

  it("caps at the top tier", () => {
    let streak: SeekStreak = IDLE_SEEK_STREAK;
    let at = 1000;
    let last = 0;
    for (let i = 0; i < SEEK_PRESSES_PER_TIER * 10; i++) {
      const step = press(streak, 1, at);
      last = step.deltaMs;
      streak = step.streak;
      at += 100;
    }
    expect(last).toBe(SEEK_TIER_STEPS_MS[SEEK_TIER_STEPS_MS.length - 1]);
  });

  it("resets on direction reversal", () => {
    let streak: SeekStreak = IDLE_SEEK_STREAK;
    let at = 1000;
    for (let i = 0; i < SEEK_PRESSES_PER_TIER * 2; i++) {
      streak = press(streak, 1, at).streak;
      at += 100;
    }
    const reversed = press(streak, -1, at + 100);
    expect(reversed.deltaMs).toBe(-SEEK_TIER_STEPS_MS[0]);
  });

  it("resets after a pause longer than the window", () => {
    let streak: SeekStreak = IDLE_SEEK_STREAK;
    let at = 1000;
    for (let i = 0; i < SEEK_PRESSES_PER_TIER * 2; i++) {
      streak = press(streak, 1, at).streak;
      at += 100;
    }
    const resumed = press(streak, 1, at + SEEK_ACCEL_WINDOW_MS + 1);
    expect(resumed.deltaMs).toBe(SEEK_TIER_STEPS_MS[0]);
  });

  it("signs the delta by direction", () => {
    expect(press(IDLE_SEEK_STREAK, -1, 1000).deltaMs).toBe(
      -SEEK_TIER_STEPS_MS[0],
    );
  });
});
