import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { DataTable } from "../src/data-table.js";
import { ContextLink, detailPath, navigationReturnTo, navigationStateForLink, projectPath } from "../src/navigation.js";

test("project routes expose exact readable scopes and escape reserved characters once", () => {
  assert.equal(projectPath("project:concurrent_development_mcp"), "/projects/project:concurrent_development_mcp");
  for (const scope of ["project:a/b", "project:a%2Fb", "project:København/研发?#", "home", "project:home"]) {
    assert.equal(decodeURIComponent(projectPath(scope).slice("/projects/".length)), scope);
  }
  assert.notEqual(projectPath("project:a/b"), projectPath("project:a%2Fb"));
  assert.notEqual(projectPath("home"), projectPath("project:home"));
});

test("entity UUIDs remain directly addressable without return-path query documents", () => {
  const id = "018f0f4d-4e45-7abc-8def-000000000011";
  const href = detailPath(`${projectPath("project:work")}/resources`, id);
  assert.equal(href, `/projects/project:work/resources/${id}`);
  const markup = renderToStaticMarkup(<MemoryRouter initialEntries={["/skills?name=exact"]}><ContextLink to={href}>Resource</ContextLink></MemoryRouter>);
  assert.match(markup, new RegExp(`href="${href}"`));
  assert.doesNotMatch(markup, /returnTo|backTrail|eyJz/);
});

test("browser-state back context unwinds asset and detail links without loops or lost filters", () => {
  const list = "/skills?project=project%3Awork&name=exact&sort=OLDEST_FIRST";
  const detail = "/skills/018f0f4d-4e45-7abc-8def-000000000011";
  const asset = `${detail}/assets/reference.md`;
  const fromList = navigationStateForLink(list, detail, null);
  assert.equal(navigationReturnTo(fromList), list);
  const fromDetail = navigationStateForLink(detail, asset, fromList);
  assert.equal(navigationReturnTo(fromDetail), detail);
  const backAtDetail = navigationStateForLink(asset, detail, fromDetail);
  assert.equal(navigationReturnTo(backAtDetail), list);
  assert.equal(navigationReturnTo(navigationStateForLink(detail, list, backAtDetail)), null);
});

test("navigation history is bounded and ignores external or malformed return paths", () => {
  const state = { backTrail: ["//example.org", "javascript:bad", "https://example.org", "/ok", "/bad\\path", "/bad\npath"] };
  assert.equal(navigationReturnTo(state), "/ok");
  assert.equal(navigationReturnTo({ returnTo: "https://example.org" }), null);
  let trail: unknown = null;
  for (let index = 0; index < 50; index++) trail = navigationStateForLink(`/item/${index}`, `/item/${index + 1}`, trail);
  assert.equal(navigationStateForLink("/last", "/next", trail).backTrail.length, 8);
});

test("shared tables retain proper headers, row identity, keyboard scrolling and empty state", () => {
  const columns = [{ key: "name", label: "Name", render: (row: { readonly id: string; readonly name: string }) => row.name }];
  const markup = renderToStaticMarkup(<DataTable caption="Resources" columns={columns} rows={[{ id: "1", name: "routes.rb" }]} rowKey={(row) => row.id} />);
  assert.match(markup, /<caption[^>]*>Resources<\/caption>/);
  assert.match(markup, /scope="col"/);
  assert.match(markup, /scope="row"/);
  assert.match(markup, /table-striped table-hover/);
  assert.match(markup, /role="region" tabindex="0"/);
  assert.doesNotMatch(markup, /<article/);
  const empty = renderToStaticMarkup(<DataTable caption="Resources" columns={columns} rows={[]} rowKey={(row) => row.id} />);
  assert.match(empty, /colSpan="1"|colspan="1"/);
  assert.match(empty, /No items to display/);
});
