export function isTizen(): boolean {
  return typeof window !== "undefined" && typeof window.tizen !== "undefined";
}

export function hasAVPlay(): boolean {
  return typeof window !== "undefined" && typeof window.webapis?.avplay !== "undefined";
}

export function exitApp(): void {
  if (isTizen()) {
    window.tizen!.application.getCurrentApplication().exit();
  } else {
    console.info("[platform] exitApp() ignored outside Tizen");
  }
}
