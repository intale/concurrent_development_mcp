import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  OperationsBatchQuery,
  OperationsBatchesQuery
} from "../src/gql/graphql.js";
import {
  nextBatchPageParameters,
  preserveBatchDetail,
  preserveBatchPage,
  previousBatchPageParameters,
  resetBatchPagination
} from "../src/operations/operation-batches-model.js";
import {
  OperationBatchDetailView,
  OperationBatchListView
} from "../src/operations/operation-batches-view.js";
import type {
  OperationBatchDetailViewProps,
  OperationBatchListViewProps
} from "../src/operations/operation-batches-view.js";

const timestamp = "2026-09-01T09:30:00.000000Z";
const summary = {
  id: "batch:uiux:05",
  targetTool: "DEVELOPMENT_ARTIFACT_CAPTURE" as const,
  status: "RUNNING" as const,
  total: 4,
  succeeded: 2,
  rejected: 1,
  pending: 1,
  notRun: 0,
  manifestDigest: `sha256:${"5".repeat(64)}`,
  createdAt: timestamp
};
const page = {
  nodes: [summary],
  pageInfo: { endCursor: "batch-cursor", hasNextPage: true }
} satisfies OperationsBatchesQuery["operationBatches"];
const batch = {
  batch: summary,
  items: {
    nodes: [{
      index: 0,
      targetTool: "DEVELOPMENT_ARTIFACT_CAPTURE" as const,
      commandId: "command-uiux-05",
      canonicalInputDigest: `sha256:${"6".repeat(64)}`,
      status: "SUCCEEDED" as const,
      outcomeStatus: "ok",
      outcomeSummary: "Artifact captured.",
      outcomeCode: null,
      finishedAt: timestamp
    }],
    pageInfo: { endCursor: "item-cursor", hasNextPage: true }
  }
} satisfies NonNullable<OperationsBatchQuery["operationBatch"]>;

const listDefaults: OperationBatchListViewProps = {
  batchHref: (batchId) => `/operations/batches/${encodeURIComponent(batchId)}?status=RUNNING`,
  canGoBack: false,
  errorMessage: null,
  hasFilters: false,
  loading: false,
  onNext: () => undefined,
  onPrevious: () => undefined,
  onRetry: () => undefined,
  page,
  pageNumber: 1,
  refreshing: false
};
const detailDefaults: OperationBatchDetailViewProps = {
  backHref: "/operations/batches?status=RUNNING&after=batch-cursor",
  batch,
  canGoBack: true,
  errorMessage: null,
  loading: false,
  onNext: () => undefined,
  onPrevious: () => undefined,
  onRetry: () => undefined,
  pageNumber: 2,
  refreshing: false
};

function renderList(overrides: Partial<OperationBatchListViewProps> = {}) {
  return renderToStaticMarkup(
    <MemoryRouter><OperationBatchListView {...listDefaults} {...overrides} /></MemoryRouter>
  );
}

function renderDetail(overrides: Partial<OperationBatchDetailViewProps> = {}) {
  return renderToStaticMarkup(
    <MemoryRouter><OperationBatchDetailView {...detailDefaults} {...overrides} /></MemoryRouter>
  );
}

test("presents progress, one primary batch action, and a spatial item detail", () => {
  const list = renderList();
  assert.match(list, /2 of 4 items succeeded/);
  assert.match(list, />Open batch/);
  assert.match(list, /batch%3Auiux%3A05\?status=RUNNING/);

  const detail = renderDetail();
  assert.match(detail, /Batch items/);
  assert.match(detail, /Artifact captured/);
  assert.match(detail, /Page 2/);
  assert.match(detail, /href="\/operations\/batches\?status=RUNNING&amp;after=batch-cursor"/);
  assert.doesNotMatch(detail, /Available batches/);
});

test("keeps stale batches visible and provides contextual initial states", () => {
  const stale = renderList({ errorMessage: "GraphQL unavailable", refreshing: true });
  assert.match(stale, /last available operation facts remain visible/);
  assert.match(stale, /Retry refresh/);
  assert.match(stale, /Refreshing/);

  assert.match(renderList({ loading: true, page: null }), /Loading operation batches/);
  assert.match(renderList({ errorMessage: "Network unavailable", page: null }), /could not be loaded/);
  assert.match(renderList({ hasFilters: true, page: { nodes: [], pageInfo: { endCursor: null, hasNextPage: false } } }), /match the applied filters/);
  assert.match(renderDetail({ batch: null }), /Batch is not available/);
});

test("binds available-data preservation and independent cursor history to batch filters", () => {
  const response: OperationsBatchesQuery = { operationBatches: page };
  const detail: OperationsBatchQuery = { operationBatch: batch };
  const filters = { sort: "NEWEST_FIRST" as const, status: "RUNNING" as const };
  assert.equal(preserveBatchPage(response, ["batches", "NEWEST_FIRST", "RUNNING", undefined], filters), response);
  assert.equal(preserveBatchPage(response, ["batches", "OLDEST_FIRST", "RUNNING", undefined], filters), undefined);
  assert.equal(preserveBatchDetail(detail, ["batch", summary.id], summary.id), detail);
  assert.equal(preserveBatchDetail(detail, ["batch", "other"], summary.id), undefined);

  const first = new URLSearchParams("status=RUNNING&tool=DEVELOPMENT_ARTIFACT_CAPTURE");
  const second = nextBatchPageParameters(first, "cursor-1");
  const itemSecond = nextBatchPageParameters(second, "item-cursor-1", "itemsAfter", "itemsTrail");
  assert.equal(itemSecond.get("after"), "cursor-1");
  assert.equal(itemSecond.get("itemsAfter"), "item-cursor-1");
  assert.equal(previousBatchPageParameters(itemSecond, "itemsAfter", "itemsTrail").has("itemsAfter"), false);
  assert.equal(previousBatchPageParameters(second).has("after"), false);
  assert.equal(resetBatchPagination(second).get("status"), "RUNNING");
});
