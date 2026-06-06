import type { Dictionary } from "./en";

const zh: Dictionary = {
  meta: {
    siteName: "Another IPTV Player",
    home: {
      title: "Another IPTV Player — 免费开源的 IPTV 播放器",
      description:
        "一款免费、开源、跨平台的 IPTV 播放器。付费播放器的全部高级功能——Xtream Codes 与 M3U 支持、离线下载、画中画、HDR——没有广告、没有跟踪、没有费用。",
    },
    faq: {
      title: "常见问题 — Another IPTV Player",
      description:
        "关于 Another IPTV Player 的常见问题——价格、提供商、隐私、支持的平台等。",
    },
    support: {
      title: "支持 — Another IPTV Player",
      description:
        "获取 Another IPTV Player 的帮助——一款免费、开源的 IPTV 播放器。联系方式、常见问题与上手指南。",
    },
    privacy: {
      title: "隐私政策 — Another IPTV Player",
      description:
        "Another IPTV Player 隐私政策。应用不收集任何个人数据；一切都保留在你的设备上。",
    },
  },

  nav: {
    features: "功能",
    screenshots: "截图",
    how: "工作原理",
    faq: "常见问题",
    support: "支持",
    getApp: "获取应用",
    github: "GitHub 仓库",
    theme: "切换配色主题",
    menu: "打开/关闭菜单",
    language: "切换语言",
  },

  hero: {
    badge: "免费开源 — 无广告，无跟踪",
    titleLine1: "所有频道。",
    titlePre: "一个 ",
    titleHighlight: "出色",
    titlePost: " 的播放器。",
    subtitle:
      "付费 IPTV 播放器的全部高级功能——Xtream Codes 与 M3U 支持、继续观看、自动播放下一集——免费，在你所有的设备上。",
    ctaAppStore: "App Store",
    ctaGooglePlay: "Google Play",
    ctaGithub: "在 GitHub 点星",
  },

  marquee: [
    "直播电视",
    "电影",
    "剧集",
    "Xtream Codes",
    "M3U / M3U8",
    "离线下载",
    "画中画",
    "HDR",
    "继续观看",
    "自动播放下一集",
    "字幕",
    "收藏",
    "10+ 种语言",
  ],

  features: {
    label: "你需要的一切",
    headingLine1: "高级功能，",
    headingLine2: "毫无附加条件。",
    intro:
      "为对标——并超越——付费播放器而生。无需订阅、无需账户、无遥测。带上你自己的提供商即可开始。",
    items: [
      {
        title: "离线下载",
        body: "下载电影和剧集以离线观看——随时随地，无需联网。内置仅 Wi-Fi 模式与存储管理。",
      },
      {
        title: "Xtream Codes API",
        body: "通过 Xtream Codes API 提供完整的直播电视、电影和剧集。",
      },
      {
        title: "M3U 与 M3U8",
        body: "从远程 URL 或本地 .m3u / .m3u8 文件添加播放列表。",
      },
      {
        title: "画中画",
        body: "将视频缩入悬浮窗口，一边处理其他事情一边继续观看。",
      },
      {
        title: "HDR 播放",
        body: "基于 mpv 的引擎，配合 HDR 色调映射，呈现忠于片源的色彩与细节。",
      },
      {
        title: "继续观看",
        body: "从上次停下的地方精确续播——并自动进入下一集。",
      },
      {
        title: "字幕工坊",
        body: "为字幕设置样式——字体、颜色、描边、位置——用时间偏移修正同步，或加载你自己的 .srt 文件。",
      },
      {
        title: "手势控制",
        body: "滑动调节亮度与音量，快进/快退 ±15 秒，长按以 2× 速度播放。",
      },
      {
        title: "全局搜索",
        body: "在全部内容中即时找到任意频道、电影或剧集。",
      },
    ],
    moreTitle: "还有更多",
    more: [
      "后台播放",
      "自动播放下一集",
      "视频、音频与字幕轨道",
      "记住你的轨道与音量选择",
      "收藏——直播、电影与剧集",
      "带续播位置的观看历史",
      "家长控制（成人内容过滤）",
      "多个播放列表",
      "画面比例：适应、填充与原始",
      "隐藏不用的分类",
      "丰富的电影与剧集详情",
      "订阅与内容统计",
      "“最近添加”行",
      "10+ 种语言",
      "无广告 · 无跟踪",
      "免费且开源",
    ],
  },

  screenshots: {
    label: "看它如何运作",
    heading: "每块屏幕上都原生。",
    view: "查看",
  },

  how: {
    label: "几分钟即可上手",
    heading: "三步搞定。无需账户。",
    steps: [
      {
        title: "带上你的提供商",
        body: "获取你的 IPTV 提供商的 Xtream Codes 信息或一个 M3U 播放列表。订阅始终属于你——我们绝不出售内容。",
      },
      {
        title: "添加你的播放列表",
        body: "输入服务器 URL、用户名和密码——或粘贴一个 M3U 链接。无需注册、无需付费、无需账户。",
      },
      {
        title: "点击播放",
        body: "在你所有的设备上，以快速、原生、无广告的体验浏览直播电视、电影和剧集。",
      },
    ],
    headsUp: "请注意",
    headsUpText:
      "Another IPTV Player 不是 IPTV 提供商，也不出售任何频道、订阅或内容。你需要带上自己支持 Xtream Codes 或 M3U 的合法提供商。使用本应用永远无需注册或付费。",
  },

  download: {
    label: "获取应用",
    heading: "永久免费——在你所有的设备上。",
    intro:
      "iOS 和 Android 通过官方商店发布并自动更新。桌面版和侧载版本发布在 GitHub Releases。",
    subs: {
      "App Store": "iPhone 与 iPad",
      "Google Play": "Android 手机与平板",
      macOS: "通用版 · Intel 与 Apple Silicon",
      Windows: "x64 · Windows 10 与 11",
      Linux: "x64 · 大多数发行版",
      "GitHub Releases": "APK、IPA 与桌面版本",
    },
  },

  openSource: {
    pillars: [
      {
        title: "100% 开源",
        body: "每一行代码都公开。审查它、复刻它、贡献它——可验证的透明。",
      },
      {
        title: "无广告，无跟踪",
        body: "我们在应用中不收集任何分析数据和遥测。你看的内容只属于你。",
      },
      {
        title: "社区驱动",
        body: "在公开环境中开发，依靠真实用户的 issue、pull request 和反馈。",
      },
    ],
    label: "支持这个项目",
    text: "免费使用，用心打造。如果它值得在你的主屏幕上占据一席之地，欢迎为它的开发提供支持。",
    coffee: "请我喝杯咖啡",
    contribute: "参与贡献",
  },

  footer: {
    tagline:
      "适用于 iOS、Android、macOS、Windows 和 Linux 的免费开源 IPTV 播放器。无广告。无跟踪。无费用。",
    product: "产品",
    help: "帮助",
    project: "项目",
    download: "下载",
    github: "GitHub",
    releases: "发布版本",
    contribute: "参与贡献",
    coffee: "请我喝杯咖啡",
    privacy: "隐私",
    rights: "采用 MIT 许可。",
    disclaimer:
      "免责声明：Another IPTV Player 不提供 IPTV 内容或订阅。请使用你自己的合法 IPTV 服务。",
  },

  supportPage: {
    eyebrow: "支持与信息",
    title: "我们随时为你提供帮助。",
    intro:
      "Another IPTV Player 是一款完全免费且开源的 IPTV 播放器。我们的目标是提供付费播放器的全部高级功能——没有任何费用或限制，依靠开源的透明。",
    notes: [
      {
        title: "我们不是 IPTV 提供商",
        body: "本应用不提供也不出售任何 IPTV 订阅或内容。",
      },
      {
        title: "无需注册或付费",
        body: "使用本应用无需注册、订阅或付费。",
      },
      {
        title: "带上你自己的提供商",
        body: "你需要已经拥有支持 Xtream Codes API 或 M3U 播放列表的 IPTV 提供商。",
      },
    ],
    howToTitle: "如何使用",
    howTo: [
      "获取你的 IPTV 提供商的 Xtream Codes 信息（服务器 URL、用户名、密码）——或一个 M3U/M3U8 播放列表链接。",
      "在应用中输入这些凭据，即可访问你的频道、电影和剧集。",
      "在每台设备上享受功能丰富、无广告、开源的 IPTV 体验。",
    ],
    whyTitle: "为什么选择 Another IPTV Player？",
    why: [
      "100% 免费，永久免费",
      "完全开源——值得信赖的透明",
      "无广告、无跟踪、无隐藏费用",
      "社区驱动的开发",
    ],
    needHelpTitle: "需要帮助？",
    needHelpText:
      "如有问题、反馈、错误报告或功能请求，请在 GitHub 或通过电子邮件与我们联系。我们会阅读每一条。",
    githubBtn: "GitHub 仓库",
    disclaimer:
      "免责声明：Another IPTV Player 不提供任何 IPTV 内容或订阅。你必须使用自己的合法 IPTV 服务。我们不认可或推广任何特定的 IPTV 提供商。",
  },

  faqPage: {
    eyebrow: "常见问题",
    title: "了解一下。",
    intro:
      "对最常被问到的问题的简短回答。仍有疑问？请在 GitHub 或通过电子邮件联系我们。",
    items: [
      {
        q: "Another IPTV Player 提供任何 IPTV 频道或内容吗？",
        a: "不。Another IPTV Player 只是一个播放器。我们不提供、不托管也不出售任何 IPTV 频道、播放列表或内容。你需要自己的 IPTV 提供商。",
      },
      {
        q: "使用这款应用需要付费吗？",
        a: "不需要。应用完全免费且开源。没有订阅、应用内购买或广告。",
      },
      {
        q: "没有 IPTV 提供商可以使用应用吗？",
        a: "不可以。你需要有效订阅，或可访问支持 Xtream Codes API 或 M3U/M3U8 播放列表的 IPTV 提供商。",
      },
      {
        q: "需要注册吗？",
        a: "无需注册。你只需输入 IPTV 提供商的凭据即可。",
      },
      {
        q: "我的个人数据安全吗？",
        a: "安全。应用不收集或存储任何个人数据。你的 IPTV 凭据仅在你的设备本地使用。",
      },
      {
        q: "Another IPTV Player 在哪些平台上可用？",
        a: "iOS（iPhone 与 iPad）、Android、macOS、Windows 和 Linux。请查看我们的网站或 GitHub 获取最新版本。",
      },
      {
        q: "如何报告错误或请求功能？",
        a: "你可以在我们的 GitHub 仓库报告问题或请求功能，或通过 bsogulcan@gmail.com 联系我们。",
      },
      {
        q: "使用 Another IPTV Player 合法吗？",
        a: "应用本身是合法软件。但你有责任确保你的 IPTV 提供商以及你访问的内容在你所在的国家/地区是合法的。",
      },
      {
        q: "我可以为项目做贡献吗？",
        a: "当然！我们欢迎开源贡献。请访问我们的 GitHub 仓库开始。",
      },
    ],
    notFound: "没有找到你的答案？",
    askGithub: "在 GitHub 提问",
    emailUs: "发邮件给我们",
  },

  privacyPage: {
    eyebrow: "隐私政策",
    title: "你的数据始终属于你。",
    lastUpdated: "最后更新",
    blocks: {
      app: {
        title: "应用",
        intro:
          "Another IPTV Player 不收集、不存储也不传输任何个人数据或用户信息。",
        points: [
          "IPTV 播放列表、凭据和频道列表仅本地存储在你的设备上。",
          "没有数据发送到我们的服务器——我们没有任何服务器。",
          "应用中不包含任何分析、广告或跟踪 SDK。",
        ],
      },
      website: {
        title: "本网站",
        p1: "本营销网站使用 Google Analytics 了解匿名、聚合的流量（例如页面浏览量和国家/地区）。这有助于我们改进网站。它不会对你进行个人身份识别，并且与应用完全分离——应用本身不包含任何分析。",
        p2: "你可以随时通过内容拦截器或 Google 的工具来阻止它。",
      },
      thirdParty: {
        title: "第三方服务",
        p1: "应用不集成任何第三方分析、广告或数据收集服务。应用建立的任何连接都直接面向你所配置的 IPTV 提供商。",
      },
      openSource: {
        title: "开源",
        before:
          "Another IPTV Player 是开源的。你可以查看完整源代码，亲自验证这些隐私做法，地址：",
        link: "GitHub",
        after: "。",
      },
      changes: {
        title: "变更",
        p1: "本隐私政策的任何更新都会在本页面上以新的“最后更新”日期体现。",
      },
      contact: {
        title: "联系",
        before: "对本政策有疑问？请在以下位置提交 issue：",
        link: "GitHub",
        middle: " 或发送邮件至 ",
        after: "。",
      },
    },
  },
};

export default zh;
