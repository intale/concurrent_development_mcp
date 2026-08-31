import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "COORDINATOR_");
  const backendOrigin = env.COORDINATOR_BACKEND_ORIGIN ?? "http://localhost:3000";

  return {
    base: "/ui/",
    build: {
      emptyOutDir: true,
      manifest: true,
      outDir: "../public/ui"
    },
    plugins: [react()],
    server: {
      proxy: {
        "/graphql": {
          changeOrigin: true,
          target: backendOrigin
        }
      }
    }
  };
});
