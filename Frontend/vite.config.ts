import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";

// Backend address is configurable via VITE_API_BASE_URL (.env) — Plan §0,
// replaces the iOS app's hardcoded LAN IP (AppConfig.swift).
// Must use loadEnv here because Vite only auto-injects .env vars into
// import.meta.env for client code, not into process.env for this config file.
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  return {
    plugins: [react()],
    server: {
      port: 5173,
      proxy: {
        "/api": {
          target: env.VITE_API_BASE_URL || "http://localhost:8080",
          changeOrigin: true,
        },
      },
    },
  };
});
