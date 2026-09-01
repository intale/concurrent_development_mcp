import assert from "node:assert/strict";
import test from "node:test";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { App } from "../src/app.js";

test("renders an accessible client-side application shell without fetching an unspecified scope", () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } }
  });
  const markup = renderToStaticMarkup(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={["/projects"]}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>
  );

  assert.match(markup, /aria-label="Toggle navigation"/);
  assert.match(markup, /aria-label="Primary navigation"/);
  assert.match(markup, /aria-label="Close navigation"/);
  assert.match(markup, /<main class="app-main">/);
  assert.match(markup, /Latest available projections/);
  assert.match(markup, /Project catalog/);
  assert.match(markup, /for="project-scope">Exact project scope/);
  assert.match(markup, /Coordinator<\/strong> read-only projection browser/);
});
