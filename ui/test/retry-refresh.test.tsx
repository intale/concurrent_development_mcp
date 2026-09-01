import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { RetryRefresh, refreshAnnouncement } from "../src/retry-refresh.js";

test("gives explicit refreshes a bounded contextual live region", () => {
  const markup = renderToStaticMarkup(
    <RetryRefresh
      announcementLabel="Project catalog"
      buttonClassName="btn btn-outline-dark"
      onRetry={() => undefined}
    >
      Retry refresh
    </RetryRefresh>
  );

  assert.match(markup, /type="button"/);
  assert.match(markup, /aria-live="polite"/);
  assert.match(markup, /aria-atomic="true"/);
  assert.doesNotMatch(markup, /Refresh request 1 sent/);
  assert.equal(
    refreshAnnouncement("Project catalog", 2),
    "Refresh request 2 sent for Project catalog. Latest available data remains visible."
  );
});
