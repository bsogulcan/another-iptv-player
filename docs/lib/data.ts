export const LINKS = {
  github: "https://github.com/bsogulcan/another-iptv-player",
  releases:
    "https://github.com/bsogulcan/another-iptv-player/releases/latest",
  appStore:
    "https://apps.apple.com/us/app/another-iptv-player/id6747290392",
  googlePlay:
    "https://play.google.com/store/apps/details?id=dev.ogos.anotheriptvplayer",
  coffee: "https://www.buymeacoffee.com/bsogulcan",
  email: "mailto:bsogulcan@gmail.com",
};

export const PLATFORMS = [
  "iOS",
  "Android",
  "macOS",
  "Windows",
  "Linux",
  "iPadOS",
];

export type Shot = { src: string; alt: string };

export const SCREENSHOTS: Record<string, Shot[]> = {
  iPhone: [
    { src: "/screenshots/iphone/home-series.png", alt: "Series home on iPhone" },
    { src: "/screenshots/iphone/home-movies.png", alt: "Movies home on iPhone" },
    {
      src: "/screenshots/iphone/home-live-tv.png",
      alt: "Live TV home on iPhone",
    },
    { src: "/screenshots/iphone/series-1.png", alt: "Series detail on iPhone" },
    { src: "/screenshots/iphone/movies-1.png", alt: "Movie detail on iPhone" },
    {
      src: "/screenshots/iphone/player-live-tv-1.png",
      alt: "Live TV player on iPhone",
    },
    {
      src: "/screenshots/iphone/player-movie.png",
      alt: "Movie player on iPhone",
    },
    {
      src: "/screenshots/iphone/player-subtitle-1.png",
      alt: "Subtitle customization on iPhone",
    },
    {
      src: "/screenshots/iphone/player-settings-1.png",
      alt: "Player settings on iPhone",
    },
    { src: "/screenshots/iphone/home-search.png", alt: "Global search on iPhone" },
    {
      src: "/screenshots/iphone/home-settings-1.png",
      alt: "Settings on iPhone",
    },
    {
      src: "/screenshots/iphone/add-playlist-xtream-code.png",
      alt: "Add Xtream Codes playlist on iPhone",
    },
  ],
  iPad: [
    { src: "/screenshots/ipad/serie.png", alt: "Series detail on iPad" },
    { src: "/screenshots/ipad/episode.png", alt: "Episode on iPad" },
    { src: "/screenshots/ipad/movies.png", alt: "Movies on iPad" },
  ],
  Android: [
    {
      src: "/screenshots/android/series-info.png",
      alt: "Series info on Android",
    },
    { src: "/screenshots/android/episodes.png", alt: "Episodes on Android" },
    { src: "/screenshots/android/movies.png", alt: "Movies on Android" },
    { src: "/screenshots/android/live.png", alt: "Live TV on Android" },
    {
      src: "/screenshots/android/playlists.png",
      alt: "Playlists on Android",
    },
    {
      src: "/screenshots/android/player-settings.png",
      alt: "Player settings on Android",
    },
  ],
};

export const DOWNLOADS = [
  { name: "App Store", href: LINKS.appStore, featured: true },
  { name: "Google Play", href: LINKS.googlePlay, featured: true },
  { name: "macOS", href: LINKS.releases },
  { name: "Windows", href: LINKS.releases },
  { name: "Linux", href: LINKS.releases },
  { name: "GitHub Releases", href: LINKS.releases },
];
