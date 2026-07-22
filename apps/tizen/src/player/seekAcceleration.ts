// Accelerating scrub: consecutive same-direction seek steps arriving within
// ACCEL_WINDOW_MS grow the step through TIER_STEPS_MS (every PRESSES_PER_TIER
// presses move up one tier). Pausing longer than the window, or reversing
// direction, drops back to the base step — slow deliberate taps always stay
// precise at 10s.

export const SEEK_ACCEL_WINDOW_MS = 600;
export const SEEK_TIER_STEPS_MS = [10_000, 30_000, 60_000];
export const SEEK_PRESSES_PER_TIER = 5;

export interface SeekStreak {
  dir: -1 | 0 | 1;
  count: number;
  lastAt: number;
}

export const IDLE_SEEK_STREAK: SeekStreak = { dir: 0, count: 0, lastAt: 0 };

export function nextSeekStep(
  streak: SeekStreak,
  dir: -1 | 1,
  nowMs: number,
): { streak: SeekStreak; deltaMs: number } {
  const continues =
    streak.dir === dir && nowMs - streak.lastAt <= SEEK_ACCEL_WINDOW_MS;
  const count = continues ? streak.count + 1 : 0;
  const tier = Math.min(
    Math.floor(count / SEEK_PRESSES_PER_TIER),
    SEEK_TIER_STEPS_MS.length - 1,
  );
  return {
    streak: { dir, count, lastAt: nowMs },
    deltaMs: dir * SEEK_TIER_STEPS_MS[tier],
  };
}
