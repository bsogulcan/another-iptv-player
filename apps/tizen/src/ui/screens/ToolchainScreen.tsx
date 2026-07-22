import { useCallback, useEffect, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { KEY, normalizeKeyCode } from "../../navigation/keys";

// Phase 0 toolchain proof: a focusable card grid plus a raw key logger.
// Verifies on a real TV that the legacy bundle runs on Chromium 56, that
// spatial navigation works with the remote, and that media/color keys arrive.

const ROWS = 3;
const COLS = 6;

interface KeyLogEntry {
  code: number;
  key: string;
  at: string;
}

function keyName(code: number): string {
  const entry = Object.entries(KEY).find(([, value]) => value === code);
  return entry ? entry[0] : "?";
}

function DemoCard({ index }: { index: number }) {
  const { ref, focused } = useFocusable();
  return (
    <div ref={ref} className={focused ? "demo-card focused" : "demo-card"}>
      {index + 1}
    </div>
  );
}

function DemoRow({ row }: { row: number }) {
  const { ref, focusKey } = useFocusable({ trackChildren: true });
  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="demo-row">
        {Array.from({ length: COLS }, (_, col) => (
          <DemoCard key={col} index={row * COLS + col} />
        ))}
      </div>
    </FocusContext.Provider>
  );
}

export function ToolchainScreen() {
  const [log, setLog] = useState<KeyLogEntry[]>([]);
  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  useEffect(() => {
    focusSelf();
  }, [focusSelf]);

  const onKeyDown = useCallback((event: KeyboardEvent) => {
    const code = normalizeKeyCode(event);
    setLog((prev) => {
      const entry: KeyLogEntry = {
        code,
        key: keyName(code),
        at: new Date().toLocaleTimeString(),
      };
      return [entry, ...prev].slice(0, 10);
    });
  }, []);

  useEffect(() => {
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onKeyDown]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="toolchain-shell">
        <main className="demo-grid">
          {Array.from({ length: ROWS }, (_, row) => (
            <DemoRow key={row} row={row} />
          ))}
        </main>

        <aside className="key-log">
          <h2>Key log</h2>
          {log.length === 0 && <p className="key-log-hint">Press remote keys…</p>}
          {log.map((entry, i) => (
            <div key={i} className="key-log-row">
              <span className="key-log-code">{entry.code}</span>
              <span className="key-log-name">{entry.key}</span>
              <span className="key-log-time">{entry.at}</span>
            </div>
          ))}
        </aside>
      </div>
    </FocusContext.Provider>
  );
}
