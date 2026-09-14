import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import {
  LatestUpdateSortControl,
  latestUpdateSortParams,
  parseLatestUpdateSort
} from "../src/latest-update-sort.js";

test("latest-update sorting is explicit and resets cursor history", () => {
  const markup = renderToStaticMarkup(
    <LatestUpdateSortControl id="example-sort" onChange={() => undefined} value="OLDEST_FIRST" />
  );
  const changed = latestUpdateSortParams(
    new URLSearchParams("status=active&after=cursor&trail=previous"),
    "OLDEST_FIRST"
  );
  const reset = latestUpdateSortParams(changed, "NEWEST_FIRST");

  assert.match(markup, /Latest update/);
  assert.match(markup, /value="OLDEST_FIRST" selected=""/);
  assert.equal(parseLatestUpdateSort("OLDEST_FIRST"), "OLDEST_FIRST");
  assert.equal(parseLatestUpdateSort("not-supported"), "NEWEST_FIRST");
  assert.equal(changed.get("sort"), "OLDEST_FIRST");
  assert.equal(changed.get("status"), "active");
  assert.equal(changed.has("after"), false);
  assert.equal(changed.has("trail"), false);
  assert.equal(reset.has("sort"), false);
});
