const en = {
  meta: {
    siteName: "Another IPTV Player",
    home: {
      title: "Another IPTV Player — Free & Open Source IPTV Streaming",
      description:
        "A free, open-source IPTV player for iPhone, iPad & Mac. All the premium features of paid players — Xtream Codes & M3U support, TV Guide (EPG), AirPlay, offline downloads, PiP, HDR — with no ads, no tracking, no fees.",
    },
    faq: {
      title: "FAQ — Another IPTV Player",
      description:
        "Frequently asked questions about Another IPTV Player — pricing, providers, privacy, supported platforms, and more.",
    },
    support: {
      title: "Support — Another IPTV Player",
      description:
        "Get help with Another IPTV Player — a free, open-source IPTV player. Contact, FAQs, and how to get started.",
    },
    privacy: {
      title: "Privacy Policy — Another IPTV Player",
      description:
        "The app has no advertising or tracking SDKs. Local storage, optional support reports, and Apple purchases are described below.",
    },
  },

  nav: {
    features: "Features",
    screenshots: "Screenshots",
    how: "How it works",
    faq: "FAQ",
    support: "Support",
    guide: "Guide",
    getApp: "Get the app",
    github: "GitHub repository",
    theme: "Toggle color theme",
    menu: "Toggle menu",
    language: "Change language",
  },

  hero: {
    badge: "Free & open source — no ads, no tracking",
    titleLine1: "Every channel.",
    titlePre: "One ",
    titleHighlight: "beautiful",
    titlePost: " player.",
    subtitle:
      "All the premium features of paid IPTV players — Xtream Codes & M3U support, TV Guide (EPG), AirPlay, continue watching — for free, on iPhone, iPad, and Mac.",
    ctaAppStore: "App Store",
    ctaGithub: "Star on GitHub",
  },

  marquee: [
    "Live TV",
    "Movies",
    "Series",
    "TV Guide (EPG)",
    "AirPlay",
    "Xtream Codes",
    "M3U / M3U8",
    "Offline Downloads",
    "Picture-in-Picture",
    "HDR",
    "Continue Watching",
    "Auto-Play Next",
    "Subtitles",
    "Favorites",
    "10+ Languages",
  ],

  features: {
    label: "Everything you need",
    headingLine1: "Built like a premium IPTV player.",
    headingLine2: "Priced like open source.",
    intro:
      "Built to match — and beat — the paid players. No subscription, no account, no telemetry. Bring your own provider and go.",
    items: [
      {
        title: "Offline Downloads",
        body: "Download movies and episodes to watch offline — anywhere, no connection needed. Wi-Fi-only mode and storage controls built in.",
      },
      {
        title: "Xtream Codes API",
        body: "Full live TV, movies, and series over the Xtream Codes API.",
      },
      {
        title: "M3U & M3U8",
        body: "Add playlists from a remote URL or a local .m3u / .m3u8 file.",
      },
      {
        title: "TV Guide (EPG)",
        body: "A full program guide for live TV — see what's on now and next, with channels grouped by collapsible categories.",
      },
      {
        title: "Picture-in-Picture",
        body: "Pop the video into a floating window — inside the app or system-wide — and keep watching while you multitask.",
      },
      {
        title: "AirPlay",
        body: "Beam live TV, movies, and series to your Apple TV — imported subtitles included.",
      },
      {
        title: "HDR Playback",
        body: "An mpv-powered engine with HDR tone-mapping for true-to-source color and detail.",
      },
      {
        title: "Continue Watching",
        body: "Resume exactly where you left off — and auto-play straight into the next episode.",
      },
      {
        title: "Subtitle Studio",
        body: "Style subtitles — font, color, outline, position — fix sync with timing offsets, or load your own .srt.",
      },
      {
        title: "Gesture Controls",
        body: "Swipe for brightness and volume, skip ±15s, long-press for 2× speed.",
      },
      {
        title: "Sort & Filter",
        body: "Sort and filter movies, series, and channels — plus flat “All Movies”, “All Series” and “All Channels” views.",
      },
      {
        title: "Global Search",
        body: "Find any channel, movie, or series across everything, instantly.",
      },
    ],
    moreTitle: "And a whole lot more",
    more: [
      "Background playback",
      "Auto-play next episode",
      "Video, audio & subtitle tracks",
      "Remembers track & volume choices",
      "Favorites — live, movies & series",
      "Watch history with resume",
      "Parental controls (adult filter)",
      "Multiple playlists",
      "Aspect ratio: Fit, Fill & Original",
      "Hide categories you don't use",
      "Rich movie & series details",
      "Subscription & content stats",
      "Recently added rows",
      "10+ languages",
      "No ads · no tracking",
      "Free & open source",
    ],
  },

  screenshots: {
    label: "See it in motion",
    heading: "Native on every screen.",
    view: "View",
  },

  how: {
    label: "Up and running in minutes",
    heading: "Three steps. No account.",
    steps: [
      {
        title: "Bring your provider",
        body: "Get your IPTV provider's Xtream Codes details or an M3U playlist. You keep your own subscription — we never sell content.",
      },
      {
        title: "Add your playlist",
        body: "Enter the server URL, username, and password — or drop in an M3U link. No sign-up, no payment, no account.",
      },
      {
        title: "Press play",
        body: "Browse live TV, movies, and series with a fast, native, ad-free experience on every device you own.",
      },
    ],
    headsUp: "Heads up",
    headsUpText:
      "Another IPTV Player is not an IPTV provider and does not sell channels, subscriptions, or content. You bring your own legal provider that supports Xtream Codes or M3U. No registration or payment is ever required to use the app.",
  },

  reviews: {
    label: "Loved by viewers",
    heading: "Straight from the App Store.",
    note: "Real reviews from the App Store. Reviews in other languages are translated — tap to see the original.",
    translated: "Translated",
    showOriginal: "Show original",
    showTranslation: "Show translation",
  },

  download: {
    label: "Get the app",
    heading: "Free, forever — on all your devices.",
    intro:
      "The iPhone & iPad app ships through the App Store with automatic updates. On the Mac, the previous-generation app is still available.",
    subs: {
      "App Store": "iPhone & iPad",
      macOS: "Previous-generation app",
      "GitHub Releases": "Source code & release notes",
    } as Record<string, string>,
  },

  openSource: {
    pillars: [
      {
        title: "100% open source",
        body: "Every line is public. Audit it, fork it, contribute — transparency you can verify.",
      },
      {
        title: "No ads, no tracking",
        body: "We collect zero analytics and zero telemetry in the app. Your viewing stays yours.",
      },
      {
        title: "Community-driven",
        body: "Built in the open with issues, pull requests, and feedback from real users.",
      },
    ],
    label: "Support the project",
    text: "Free to use, made with care. If it earns a place on your home screen, consider fueling its development.",
    sponsor: "Sponsor on GitHub",
    contribute: "Contribute",
  },

  footer: {
    tagline:
      "A free & open-source IPTV player for iPhone, iPad, and Mac. No ads. No tracking. No fees.",
    product: "Product",
    help: "Help",
    project: "Project",
    download: "Download",
    github: "GitHub",
    releases: "Releases",
    contribute: "Contribute",
    sponsor: "Sponsor on GitHub",
    privacy: "Privacy Policy",
    rights: "MIT Licensed.",
    disclaimer:
      "Disclaimer: Another IPTV Player does not provide IPTV content or subscriptions. Use your own legal IPTV service.",
  },

  supportPage: {
    eyebrow: "Support & Information",
    title: "We're here to help.",
    intro:
      "Another IPTV Player is a completely free and open-source IPTV player. Our goal is to deliver all the premium features of paid players — without any cost or restrictions, powered by the transparency of open source.",
    notes: [
      {
        title: "We are not an IPTV provider",
        body: "This application does not offer or sell any IPTV subscriptions or content.",
      },
      {
        title: "No registration or payment",
        body: "There is no sign-up, subscription, or payment required to use the app.",
      },
      {
        title: "Bring your own provider",
        body: "You must already have an IPTV provider that supports the Xtream Codes API or M3U playlists.",
      },
    ],
    howToTitle: "How to use",
    howTo: [
      "Obtain your IPTV provider's Xtream Codes details (server URL, username, password) — or an M3U/M3U8 playlist link.",
      "Enter these credentials in the app to access your channels, movies, and series.",
      "Enjoy a feature-rich, ad-free, open-source IPTV experience on every device.",
    ],
    whyTitle: "Why Another IPTV Player?",
    why: [
      "100% free, forever",
      "Completely open source — transparency you can trust",
      "No ads, no tracking, no hidden fees",
      "Community-driven development",
    ],
    needHelpTitle: "Need help?",
    needHelpText:
      "For questions, feedback, bug reports, or feature requests, reach out on GitHub or by email. We read everything.",
    githubBtn: "GitHub repository",
    disclaimer:
      "Disclaimer: Another IPTV Player does not provide any IPTV content or subscriptions. You must use your own legal IPTV service. We do not endorse or promote any specific IPTV providers.",
  },

  faqPage: {
    eyebrow: "Frequently asked questions",
    title: "Good to know.",
    intro:
      "The short answers to the things people ask most. Still stuck? Reach out on GitHub or by email.",
    items: [
      {
        q: "Does Another IPTV Player provide any IPTV channels or content?",
        a: "No. Another IPTV Player is just a player. We do not provide, host, or sell any IPTV channels, playlists, or content. You need to use your own IPTV provider.",
      },
      {
        q: "Do I need to pay to use the app?",
        a: "The app remains free. iOS offers optional, one-time consumable tips through Apple; they unlock no features and are not subscriptions.",
      },
      {
        q: "Can I use the app without an IPTV provider?",
        a: "No. You need an active subscription or access to an IPTV provider that supports the Xtream Codes API or M3U/M3U8 playlists to use Another IPTV Player.",
      },
      {
        q: "Is registration required?",
        a: "No registration is required. You simply enter your IPTV provider credentials to use the app.",
      },
      {
        q: "Is my personal data safe?",
        a: "IPTV playlists, credentials, and channel lists are stored locally on your device only. Support in iOS 3.0.0 is optional. Reports include your message, app and iOS versions, device model, and date. Sending email also shares your sender name and email address with us and our email provider, Gmail. Nothing is sent automatically.",
      },
      {
        q: "Which platforms is Another IPTV Player available on?",
        a: "iOS (iPhone & iPad) via the App Store. On macOS, the previous-generation app is still available. Check our website or GitHub for the latest updates.",
      },
      {
        q: "How do I report a bug or request a feature?",
        a: "You can report issues or request features on our GitHub repository, or contact us at bsogulcan@gmail.com.",
      },
      {
        q: "Is it legal to use Another IPTV Player?",
        a: "The app itself is legal software. However, you are responsible for ensuring that your IPTV provider and the content you access are legal in your country.",
      },
      {
        q: "Can I contribute to the project?",
        a: "Absolutely! We welcome open-source contributions. Visit our GitHub repository to get started.",
      },
    ],
    notFound: "Didn't find your answer?",
    askGithub: "Ask on GitHub",
    emailUs: "Email us",
  },

  privacyPage: {
    eyebrow: "Privacy Policy",
    title: "Your data stays yours.",
    lastUpdated: "Last updated",
    blocks: {
      app: {
        title: "The App",
        intro:
          "The app has no advertising or tracking SDKs. Local storage, optional support reports, and Apple purchases are described below.",
        points: [
          "IPTV playlists, credentials, and channel lists are stored locally on your device only.",
          "Support in iOS 3.0.0 is optional. Reports include your message, app and iOS versions, device model, and date. Sending email also shares your sender name and email address with us and our email provider, Gmail. Nothing is sent automatically.",
          "Diagnostic attachments are off by default and can be previewed. Local logs include app events, playback errors, and API response details; the archive is size-limited with a seven-day age limit. Recognized URLs and credential fields are redacted, but review the content before sharing.",
          "Support emails and attachments are used to answer requests and troubleshoot, not for advertising or tracking. We delete them from our support mailbox within 30 days after the request closes. For earlier deletion, email bsogulcan@gmail.com. Your email or sharing provider's retention policies apply to its copies.",
          "The app remains free. iOS offers optional, one-time consumable tips through Apple; they unlock no features and are not subscriptions. Apple handles payment. We do not receive card or bank details, and the app does not upload purchase records to a developer-operated server.",
        ],
      },
      website: {
        title: "This Website",
        p1: "This marketing website uses Google Analytics and Vercel Web Analytics to understand anonymous, aggregate traffic (such as page views and country). This helps us improve the site. It does not personally identify you, and it is completely separate from the app — the app itself contains no analytics.",
        p2: "You can block this at any time with a content blocker or by opting out via Google's tools.",
      },
      thirdParty: {
        title: "Third-Party Services",
        p1: "Connections include your IPTV provider and services needed to display content, Apple's purchase services, and email or sharing services you choose for support. Their privacy policies apply. Diagnostic logs are not automatically uploaded.",
      },
      openSource: {
        title: "Open Source",
        before: "Another IPTV Player is open source. You can review the complete source code to verify these privacy practices for yourself on ",
        link: "GitHub",
        after: ".",
      },
      changes: {
        title: "Changes",
        p1: 'Any updates to this privacy policy will be reflected on this page with a new "last updated" date.',
      },
      contact: {
        title: "Contact",
        before: "Questions about this policy? Open an issue on ",
        link: "GitHub",
        middle: " or email ",
        after: ".",
      },
    },
  },
};

export type Dictionary = typeof en;
export default en;
