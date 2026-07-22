import { hasAVPlay } from "../env/platform";
import { AVPlayAdapter } from "./AVPlayAdapter";
import { Html5VideoAdapter } from "./Html5VideoAdapter";
import { PlayerPort } from "./PlayerPort";

export function createPlayer(): PlayerPort {
  return hasAVPlay() ? new AVPlayAdapter() : new Html5VideoAdapter();
}
