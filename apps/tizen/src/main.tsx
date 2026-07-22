import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";
import { initSpatialNavigation } from "./navigation/focus";
import { registerTVKeys } from "./navigation/keys";
import { isTizen } from "./env/platform";
import "./ui/styles/base.css";

initSpatialNavigation();
registerTVKeys();

// Desktop dev nicety: scale the fixed 1920×1080 TV canvas to fit the browser
// window. On the TV the viewport is exactly 1920×1080, so this never applies.
function fitCanvasToWindow(): void {
  if (isTizen()) return;
  const root = document.getElementById("root");
  if (!root) return;
  const scale = Math.min(
    window.innerWidth / 1920,
    window.innerHeight / 1080,
    1,
  );
  const offsetX = Math.max((window.innerWidth - 1920 * scale) / 2, 0);
  root.style.transformOrigin = "top left";
  root.style.transform = `translateX(${offsetX}px) scale(${scale})`;
}
window.addEventListener("resize", fitCanvasToWindow);
fitCanvasToWindow();

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
