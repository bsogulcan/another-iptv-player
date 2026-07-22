import { IncomingMessage, ServerResponse } from "node:http";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import { defineConfig, Plugin } from "vite";
import react from "@vitejs/plugin-react";
import legacy from "@vitejs/plugin-legacy";

// Tizen 4.0 TVs (2018 models) run Chromium M56: no <script type="module">,
// so a legacy (SystemJS) bundle must be available. Modern chunks are also
// emitted (module/nomodule split): recent TVs (Tizen 5.5+, Chromium 69+)
// load the smaller native-ES bundle instead of paying the ES5+regenerator
// tax, and only genuine M56 devices fall back to SystemJS.

/**
 * Dev-only CORS escape hatch: /__proxy?url=<encoded> forwards the request
 * server-side. On the TV the packaged app is CORS-exempt (config.xml
 * <access origin="*">), so this middleware never ships.
 */
function devProxy(): Plugin {
  return {
    name: "aiptv-dev-proxy",
    configureServer(server) {
      server.middlewares.use(
        "/__proxy",
        (req: IncomingMessage, res: ServerResponse) => {
          const target = new URL(
            req.url ?? "",
            "http://localhost",
          ).searchParams.get("url");
          if (!target) {
            res.statusCode = 400;
            res.end("missing url param");
            return;
          }
          let parsed: URL;
          try {
            parsed = new URL(target);
          } catch {
            res.statusCode = 400;
            res.end("invalid url");
            return;
          }
          const doRequest =
            parsed.protocol === "https:" ? httpsRequest : httpRequest;
          const upstream = doRequest(
            parsed,
            { method: "GET", headers: { "user-agent": "AnotherIPTVPlayer-dev" } },
            (upstreamRes) => {
              res.statusCode = upstreamRes.statusCode ?? 502;
              const contentType = upstreamRes.headers["content-type"];
              if (contentType) res.setHeader("content-type", contentType);
              upstreamRes.pipe(res);
            },
          );
          upstream.on("error", (err) => {
            res.statusCode = 502;
            res.end(`proxy error: ${err.message}`);
          });
          upstream.end();
        },
      );
    },
  };
}

/**
 * Packaged Tizen apps boot from file://, where stock Chromium blocks
 * EXTERNAL module scripts (opaque-origin CORS) while INLINE module scripts
 * still execute. On such a runtime plugin-legacy's modern-browser detector
 * (inline module) passes and suppresses the SystemJS fallback, the module
 * entry then fails to load, and nothing boots — black screen on exactly the
 * newest TVs. Safety net: if the module entry errors, boot the legacy path
 * manually. On old TVs the module tag is ignored entirely (no error event),
 * and nomodule handles them, so this can never double-boot.
 */
function moduleFallback(): Plugin {
  return {
    name: "aiptv-module-fallback",
    transformIndexHtml: {
      order: "post",
      handler(html: string): string {
        if (html.indexOf("vite-legacy-entry") === -1) return html;
        const marked = html.replace(
          /<script type="module" crossorigin src="([^"]+)"><\/script>/,
          '<script type="module" crossorigin src="$1" onerror="window.__aiptvModuleFailed=1"></script>',
        );
        const fallback =
          "<script>window.addEventListener(\"load\",function(){" +
          "if(!window.__aiptvModuleFailed)return;" +
          'var p=document.getElementById("vite-legacy-polyfill");' +
          'var e=document.getElementById("vite-legacy-entry");' +
          "if(!p||!e)return;" +
          'var s=document.createElement("script");s.src=p.src;' +
          's.onload=function(){System.import(e.getAttribute("data-src"))};' +
          "document.body.appendChild(s)});</script>";
        return marked.replace("</body>", fallback + "</body>");
      },
    },
  };
}

export default defineConfig({
  base: "./",
  plugins: [
    react(),
    legacy({
      targets: ["chrome >= 56"],
      renderModernChunks: true,
      // No modernTargets override: plugin-legacy's guard injects import.meta
      // into the modern entry, so anything below Chromium 64 fails to parse
      // it and the inline detector routes those TVs to the legacy path —
      // lowering the transpile floor would be pure bloat nobody can run.
    }),
    moduleFallback(),
    devProxy(),
  ],
  build: {
    outDir: "dist",
    assetsDir: "assets",
  },
  server: {
    port: 5173,
  },
});
