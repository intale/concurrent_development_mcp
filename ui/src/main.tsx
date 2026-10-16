import { StrictMode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import ReactRailsUJS from "react_ujs";
import { BrowserRouter } from "react-router-dom";
import { App } from "./app.js";
import { MarkdownStylesContext } from "./markdown/markdown-preview.js";
import markdownStyles from "github-markdown-css/github-markdown-light.css?inline";
import "@adminlte/react/css";
import "bootstrap-icons/font/bootstrap-icons.css";
import "bootstrap/dist/js/bootstrap.bundle.min.js";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      refetchOnWindowFocus: true,
      retry: 1,
      staleTime: 5_000
    }
  }
});

export function CoordinatorApp() {
  return (
    <StrictMode>
      <MarkdownStylesContext.Provider value={markdownStyles}>
        <QueryClientProvider client={queryClient}>
          <BrowserRouter>
            <App />
          </BrowserRouter>
        </QueryClientProvider>
      </MarkdownStylesContext.Provider>
    </StrictMode>
  );
}

ReactRailsUJS.getConstructor = (className) =>
  className === "CoordinatorApp" ? CoordinatorApp : undefined;
