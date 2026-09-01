import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { CopyIdentifier, copyResultAnnouncement } from "../src/copy-identifier.js";

test("keeps long identifiers readable and exposes a touch-sized copy action", () => {
  const markup = renderToStaticMarkup(
    <CopyIdentifier label="WorkItem ID" value="WI-UIUX-11-RESPONSIVE-A11Y-STATE" />
  );

  assert.match(markup, /flex-column flex-sm-row/);
  assert.match(markup, /text-break flex-grow-1/);
  assert.match(markup, /aria-label="Copy WorkItem ID"/);
  assert.match(markup, /class="btn btn-outline-secondary"/);
  assert.match(markup, /aria-live="polite"/);
  assert.equal(copyResultAnnouncement("WorkItem ID", true), "WorkItem ID copied.");
  assert.equal(copyResultAnnouncement("WorkItem ID", false), "WorkItem ID could not be copied.");
});
