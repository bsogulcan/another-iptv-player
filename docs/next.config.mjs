/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "export",
  trailingSlash: true,
  outputFileTracingRoot: import.meta.dirname,
  images: {
    unoptimized: true,
  },
  // Dev-only convenience: redirect "/" to the default locale.
  // Ignored by `output: export` (production uses public/index.html, which
  // detects the visitor's language), but active under `next dev`.
  async redirects() {
    return [{ source: "/", destination: "/en", permanent: false }];
  },
};

export default nextConfig;
