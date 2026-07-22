// Ambient type declarations for the Samsung TV runtime (window.tizen / window.webapis).
// Only the surface this app actually uses is declared.

interface TizenInputDeviceKey {
  name: string;
  code: number;
}

interface TizenInputDevice {
  registerKey(keyName: string): void;
  unregisterKey(keyName: string): void;
  getSupportedKeys(): TizenInputDeviceKey[];
}

interface TizenApplication {
  exit(): void;
  hide(): void;
}

interface TizenApplicationManager {
  getCurrentApplication(): TizenApplication;
}

interface Tizen {
  tvinputdevice: TizenInputDevice;
  application: TizenApplicationManager;
}

type AVPlayPlayerState =
  | "NONE"
  | "IDLE"
  | "READY"
  | "PLAYING"
  | "PAUSED";

interface AVPlayStreamInfo {
  index: number;
  type: "AUDIO" | "TEXT" | "VIDEO";
  extra_info: string;
}

interface AVPlayListener {
  onbufferingstart?: () => void;
  onbufferingprogress?: (percent: number) => void;
  onbufferingcomplete?: () => void;
  oncurrentplaytime?: (currentTimeMs: number) => void;
  onstreamcompleted?: () => void;
  onerror?: (eventType: string) => void;
  onevent?: (eventType: string, eventData: string) => void;
  onsubtitlechange?: (duration: string, text: string) => void;
}

interface AVPlay {
  open(url: string): void;
  close(): void;
  prepare(): void;
  prepareAsync(successCallback?: () => void, errorCallback?: (error: unknown) => void): void;
  play(): void;
  pause(): void;
  stop(): void;
  seekTo(ms: number, successCallback?: () => void, errorCallback?: () => void): void;
  getState(): AVPlayPlayerState;
  getCurrentTime(): number;
  getDuration(): number;
  setListener(listener: AVPlayListener): void;
  setDisplayRect(x: number, y: number, width: number, height: number): void;
  setDisplayMethod(method: string): void;
  setStreamingProperty(property: string, value: string): void;
  getTotalTrackInfo(): AVPlayStreamInfo[];
  setSelectTrack(type: "AUDIO" | "TEXT" | "VIDEO", index: number): void;
  suspend(): void;
  restore(url?: string, resumeTimeMs?: number, prepare?: boolean): void;
  setTimeoutForBuffering(seconds: number): void;
}

interface TizenProductInfo {
  isUdPanelSupported(): boolean;
  is8KPanelSupported?(): boolean;
}

interface WebApis {
  avplay: AVPlay;
  productinfo?: TizenProductInfo;
}

interface Window {
  tizen?: Tizen;
  webapis?: WebApis;
}
