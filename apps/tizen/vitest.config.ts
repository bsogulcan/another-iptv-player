import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
  },
  resolve: {
    alias: {
      "@fixtures": fileURLToPath(
        new URL("../../shared/fixtures", import.meta.url),
      ),
      "@": fileURLToPath(new URL("src", import.meta.url)),
    },
  },
});
