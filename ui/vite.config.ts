import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  base: "/ui/",
  build: {
    cssCodeSplit: false,
    emptyOutDir: true,
    outDir: "../public/ui",
    rollupOptions: {
      output: {
        assetFileNames: (assetInfo) =>
          assetInfo.names.some((name) => name.endsWith(".css"))
            ? "coordinator-ui.css"
            : "assets/[name]-[hash][extname]",
        entryFileNames: "coordinator-ui.js"
      }
    }
  },
  plugins: [react()]
});
