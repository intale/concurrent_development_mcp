import { useEffect, useMemo, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { fetchOperationBatch, fetchOperationBatches } from "./operation-batches-api.js";
import {
  nextBatchPageParameters,
  OPERATION_BATCH_SORTS,
  OPERATION_BATCH_STATUSES,
  OPERATION_BATCH_TOOLS,
  parseOperationBatchSort,
  parseOperationBatchStatus,
  parseOperationBatchTool,
  preserveBatchDetail,
  preserveBatchPage,
  previousBatchPageParameters,
  resetBatchPagination
} from "./operation-batches-model.js";
import {
  OperationBatchDetailView,
  OperationBatchListView
} from "./operation-batches-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function OperationBatchesPage() {
  const { batchId } = useParams<{ batchId: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const sort = parseOperationBatchSort(searchParams.get("sort"));
  const status = parseOperationBatchStatus(searchParams.get("status"));
  const targetTool = parseOperationBatchTool(searchParams.get("tool"));
  const after = searchParams.get("after");
  const itemsAfter = searchParams.get("itemsAfter");
  const pageNumber = searchParams.getAll("trail").length + 1;
  const itemPageNumber = searchParams.getAll("itemsTrail").length + 1;
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    document.title = batchId ? `${batchId} · Operations · Coordinator` : "Operation batches · Coordinator";
    headingRef.current?.focus();
  }, [batchId]);

  const filters = useMemo(() => ({
    sort,
    ...(status ? { status } : {}),
    ...(targetTool ? { targetTool } : {})
  }), [sort, status, targetTool]);
  const batches = useQuery({
    queryKey: ["operation-batches", sort, status, targetTool, after],
    queryFn: ({ signal }) => fetchOperationBatches(filters, after, signal),
    enabled: batchId === undefined,
    placeholderData: (previousData, previousQuery) => preserveBatchPage(
      previousData,
      previousQuery?.queryKey,
      filters
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const batch = useQuery({
    queryKey: ["operation-batch", batchId, itemsAfter],
    queryFn: ({ signal }) => fetchOperationBatch(batchId ?? "", itemsAfter, signal),
    enabled: batchId !== undefined,
    placeholderData: (previousData, previousQuery) => preserveBatchDetail(
      previousData,
      previousQuery?.queryKey,
      batchId ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const updateFilter = (name: "sort" | "status" | "tool", value: string) => {
    const next = resetBatchPagination(searchParams);
    if (value && !(name === "sort" && value === "NEWEST_FIRST")) next.set(name, value);
    else next.delete(name);
    setSearchParams(next);
  };
  const collectionParameters = new URLSearchParams(searchParams);
  collectionParameters.delete("itemsAfter");
  collectionParameters.delete("itemsTrail");
  const collectionHref = `/operations/batches${collectionParameters.size > 0 ? `?${collectionParameters}` : ""}`;
  const error = batchId ? batch.error : batches.error;
  const errorMessage = error instanceof Error ? error.message : null;

  return (
    <>
      <div className="app-content-header">
        <div className="container-fluid">
          <nav aria-label="Breadcrumb">
            <ol className="breadcrumb mb-2">
              <li className="breadcrumb-item"><Link to="/projects">Projects</Link></li>
              {batchId ? <li className="breadcrumb-item"><Link to={collectionHref}>Operation batches</Link></li> : null}
              <li aria-current="page" className="breadcrumb-item active">{batchId ?? "Operations"}</li>
            </ol>
          </nav>
          <h1 className="mb-0" ref={headingRef} tabIndex={-1}>{batchId ? "Operation batch" : "Operation batches"}</h1>
        </div>
      </div>
      <div className="app-content">
        <div className="container-fluid vstack gap-4">
          <p className="text-body-secondary mb-0">
            Global asynchronous batch progress is shown without inferring ownership by a Project.
          </p>
          {batchId ? (
            <OperationBatchDetailView
              backHref={collectionHref}
              batch={batch.data?.operationBatch ?? null}
              canGoBack={searchParams.has("itemsTrail")}
              errorMessage={errorMessage}
              loading={batch.isPending}
              onNext={() => {
                const cursor = batch.data?.operationBatch?.items.pageInfo.endCursor;
                if (cursor) setSearchParams(nextBatchPageParameters(searchParams, cursor, "itemsAfter", "itemsTrail"));
              }}
              onPrevious={() => setSearchParams(previousBatchPageParameters(searchParams, "itemsAfter", "itemsTrail"))}
              onRetry={() => { void batch.refetch(); }}
              pageNumber={itemPageNumber}
              refreshing={batch.isFetching && batch.data !== undefined}
            />
          ) : (
            <>
              <form className="card card-outline card-dark" onSubmit={(event) => event.preventDefault()}>
                <div className="card-header"><h2 className="card-title">Filter batches</h2></div>
                <div className="card-body row g-3">
                  <div className="col-12 col-md-4">
                    <label className="form-label" htmlFor="batch-sort">Order</label>
                    <select className="form-select" id="batch-sort" onChange={(event) => updateFilter("sort", event.target.value)} value={sort}>
                      {OPERATION_BATCH_SORTS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                    </select>
                  </div>
                  <div className="col-12 col-md-4">
                    <label className="form-label" htmlFor="batch-status">Status</label>
                    <select className="form-select" id="batch-status" onChange={(event) => updateFilter("status", event.target.value)} value={status ?? ""}>
                      <option value="">All statuses</option>
                      {OPERATION_BATCH_STATUSES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                    </select>
                  </div>
                  <div className="col-12 col-md-4">
                    <label className="form-label" htmlFor="batch-tool">Target tool</label>
                    <select className="form-select" id="batch-tool" onChange={(event) => updateFilter("tool", event.target.value)} value={targetTool ?? ""}>
                      <option value="">All target tools</option>
                      {OPERATION_BATCH_TOOLS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                    </select>
                  </div>
                </div>
              </form>
              <OperationBatchListView
                batchHref={(id) => `/operations/batches/${encodeURIComponent(id)}${searchParams.size > 0 ? `?${searchParams}` : ""}`}
                canGoBack={searchParams.has("trail")}
                errorMessage={errorMessage}
                hasFilters={status !== undefined || targetTool !== undefined}
                loading={batches.isPending}
                onNext={() => {
                  const cursor = batches.data?.operationBatches.pageInfo.endCursor;
                  if (cursor) setSearchParams(nextBatchPageParameters(searchParams, cursor));
                }}
                onPrevious={() => setSearchParams(previousBatchPageParameters(searchParams))}
                onRetry={() => { void batches.refetch(); }}
                page={batches.data?.operationBatches ?? null}
                pageNumber={pageNumber}
                refreshing={batches.isFetching && batches.data !== undefined}
              />
            </>
          )}
        </div>
      </div>
    </>
  );
}
