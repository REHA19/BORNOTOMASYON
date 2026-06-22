import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Backend address is configurable via VITE_API_BASE_URL (.env) — Plan §0,
// replaces the iOS app's hardcoded LAN IP (AppConfig.swift).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": {
        target: process.env.VITE_API_BASE_URL ?? "http://localhost:8080",
        changeOrigin: true,
      },
    },
  },
});
