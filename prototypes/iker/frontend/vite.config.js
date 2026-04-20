import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Port 5176 — avoids collisions with Kieran (5174) and Rosalie (5175).
// Proxies /api to the Orbit Together FastAPI backend on 8030.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5176,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:8030",
        changeOrigin: true,
      },
    },
  },
});
