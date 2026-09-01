import assert from "node:assert/strict";
import test from "node:test";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import { App } from "../src/app.js";
import type {
  AuditCommandReceiptQuery,
  AuditCommandReceiptsQuery
} from "../src/gql/graphql.js";
import {
  nextReceiptPageParameters,
  preserveReceiptDetail,
  preserveReceiptPage,
  previousReceiptPageParameters,
  resetReceiptPagination
} from "../src/audit/command-receipts-model.js";
import {
  CommandReceiptDetailView,
  CommandReceiptListView
} from "../src/audit/command-receipts-view.js";
import type {
  CommandReceiptDetailViewProps,
  CommandReceiptListViewProps
} from "../src/audit/command-receipts-view.js";

const timestamp = "2026-09-01T08:30:00.000000Z";
const receipt = {
  commandId: "cmd:uiux:05",
  toolName: "work_item_acquire",
  status: "OK" as const,
  summary: "WorkItem acquired.",
  receipt: "cmd:uiux:05",
  completedAt: timestamp,
  warnings: ["Projection may still be catching up."],
  nextActionTools: ["lease_set_reserve"],
  emittedEvents: [{
    id: "018f0f4d-4e45-7abc-8def-000000000081",
    type: "WorkItemAcquired",
    streamContext: "DevelopmentPlanning",
    streamName: "WorkItem",
    streamId: "WI-UIUX-05",
    streamRevision: 3
  }]
} satisfies NonNullable<AuditCommandReceiptQuery["commandReceipt"]>;
const page = {
  nodes: [receipt],
  pageInfo: { endCursor: "receipt-cursor", hasNextPage: true }
} satisfies AuditCommandReceiptsQuery["commandReceipts"];

const listDefaults: CommandReceiptListViewProps = {
  canGoBack: false,
  errorMessage: null,
  hasFilters: false,
  loading: false,
  loadingRequestedPage: false,
  onNext: () => undefined,
  onPrevious: () => undefined,
  onRetry: () => undefined,
  page,
  pageNumber: 1,
  receiptHref: (commandId) => `/audit/command-receipts/${encodeURIComponent(commandId)}?tool=work_item_acquire`
};
const detailDefaults: CommandReceiptDetailViewProps = {
  backHref: "/audit/command-receipts?tool=work_item_acquire",
  errorMessage: null,
  loading: false,
  onRetry: () => undefined,
  receipt
};

function renderList(overrides: Partial<CommandReceiptListViewProps> = {}) {
  return renderToStaticMarkup(
    <MemoryRouter><CommandReceiptListView {...listDefaults} {...overrides} /></MemoryRouter>
  );
}

function renderDetail(overrides: Partial<CommandReceiptDetailViewProps> = {}) {
  return renderToStaticMarkup(
    <MemoryRouter><CommandReceiptDetailView {...detailDefaults} {...overrides} /></MemoryRouter>
  );
}

test("presents one primary receipt action and a spatial detail route", () => {
  const list = renderList();
  assert.match(list, /work_item_acquire/);
  assert.match(list, />Open receipt/);
  assert.match(list, /cmd%3Auiux%3A05\?tool=work_item_acquire/);
  assert.match(list, /1 emitted event/);

  const detail = renderDetail();
  assert.match(detail, /Emitted event facts/);
  assert.match(detail, /WorkItemAcquired/);
  assert.match(detail, /href="\/audit\/command-receipts\?tool=work_item_acquire"/);
  assert.doesNotMatch(detail, /Available receipts/);
});

test("keeps stale facts visible and provides contextual initial states", () => {
  const stale = renderList({ errorMessage: "GraphQL unavailable" });
  assert.match(stale, /last available audit facts remain visible/);
  assert.match(stale, /Retry refresh/);
  assert.doesNotMatch(stale, />Refreshing/);
  assert.match(renderList({ loadingRequestedPage: true }), /Loading the requested page/);

  assert.match(renderList({ loading: true, page: null }), /Loading command receipts/);
  assert.match(renderList({ errorMessage: "Network unavailable", page: null }), /could not be loaded/);
  assert.match(renderList({ hasFilters: true, page: { nodes: [], pageInfo: { endCursor: null, hasNextPage: false } } }), /match the applied filters/);
  assert.match(renderDetail({ receipt: null }), /Receipt is not available/);
});

test("binds available-data preservation and cursor history to receipt filters", () => {
  const response: AuditCommandReceiptsQuery = { commandReceipts: page };
  const detail: AuditCommandReceiptQuery = { commandReceipt: receipt };
  assert.equal(preserveReceiptPage(response, ["audit", "work_item_acquire", "OK"], "work_item_acquire", "OK"), response);
  assert.equal(preserveReceiptPage(response, ["audit", "other", "OK"], "work_item_acquire", "OK"), undefined);
  assert.equal(preserveReceiptDetail(detail, ["audit", receipt.commandId], receipt.commandId), detail);
  assert.equal(preserveReceiptDetail(detail, ["audit", "other"], receipt.commandId), undefined);

  const first = new URLSearchParams("tool=work_item_acquire&status=OK");
  const second = nextReceiptPageParameters(first, "cursor-1");
  const third = nextReceiptPageParameters(second, "cursor-2");
  assert.equal(third.get("after"), "cursor-2");
  assert.deepEqual(third.getAll("trail"), ["", "cursor-1"]);
  const previous = previousReceiptPageParameters(third);
  assert.equal(previous.get("after"), "cursor-1");
  assert.equal(previous.get("tool"), "work_item_acquire");
  assert.equal(resetReceiptPagination(third).has("after"), false);
});

test("makes both global workspaces discoverable and preserves collection state from detail", () => {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  queryClient.setQueryData(["audit-command-receipt", receipt.commandId], { commandReceipt: receipt });
  const markup = renderToStaticMarkup(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[`/audit/command-receipts/${encodeURIComponent(receipt.commandId)}?tool=work_item_acquire&status=OK&after=cursor-1&trail=`]}>
        <App />
      </MemoryRouter>
    </QueryClientProvider>
  );

  assert.match(markup, />Command receipts</);
  assert.match(markup, />Operation batches</);
  assert.match(markup, /WorkItemAcquired/);
  assert.match(markup, /href="\/audit\/command-receipts\?tool=work_item_acquire&amp;status=OK&amp;after=cursor-1&amp;trail="/);
  assert.doesNotMatch(markup, /Filter receipts/);
});
