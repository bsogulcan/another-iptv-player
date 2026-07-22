import { init } from "@noriginmedia/norigin-spatial-navigation";

export function initSpatialNavigation(): void {
  init({
    debug: false,
    visualDebug: false,
    // TV remotes auto-repeat keydown at 20-30Hz on long-press; unthrottled,
    // every repeat runs a full spatial-nav measurement pass plus renders.
    throttle: 120,
    throttleKeypresses: true,
  });
}
