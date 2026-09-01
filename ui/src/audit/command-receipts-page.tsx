import { useEffect, useMemo, useRef, useState } from "react";
import type { FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import { fetchCommandReceipt, fetchCommandReceipts } from "./command-receipts-api.js";
import {
  COMMAND_RECEIPT_STATUSES,
  nextReceiptPageParameters,
  parseCommandReceiptStatus,
  preserveReceiptDetail,
  preserveReceiptPage,
  previousReceiptPageParameters,
  resetReceiptPagination
} from "./command-receipts-model.js";
import {
  CommandReceiptDetailView,
  CommandReceiptListView
} from "./command-receipts-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function CommandReceiptsPage() {
  const { commandId } = useParams<{ commandId: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const toolName = searchParams.get("tool")?.trim() ?? "";
  const status = parseCommandReceiptStatus(searchParams.get("status"));
  const after = searchParams.get("after");
  const pageNumber = searchParams.getAll("trail").length + 1;
  const [toolDraft, setToolDraft] = useState(toolName);
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => setToolDraft(toolName), [toolName]);
  useEffect(() => {
    document.title = commandId ? `${commandId} · Audit · Coordinator` : "Command receipts · Coordinator";
    headingRef.current?.focus();
  }, [commandId]);

  const filters = useMemo(() => ({
    ...(toolName ? { toolName } : {}),
    ...(status ? { status } : {})
  }), [status, toolName]);
  const receipts = useQuery({
    queryKey: ["audit-command-receipts", toolName, status, after],
    queryFn: ({ signal }) => fetchCommandReceipts(filters, after, signal),
    enabled: commandId === undefined,
    placeholderData: (previousData, previousQuery) => preserveReceiptPage(
      previousData,
      previousQuery?.queryKey,
      toolName,
      status
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const receipt = useQuery({
    queryKey: ["audit-command-receipt", commandId],
    queryFn: ({ signal }) => fetchCommandReceipt(commandId ?? "", signal),
    enabled: commandId !== undefined,
    placeholderData: (previousData, previousQuery) => preserveReceiptDetail(
      previousData,
      previousQuery?.queryKey,
      commandId ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const submitTool = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const next = resetReceiptPagination(searchParams);
    const tool = toolDraft.trim();
    if (tool) next.set("tool", tool);
    else next.delete("tool");
    setSearchParams(next);
  };
  const changeStatus = (value: string) => {
    const next = resetReceiptPagination(searchParams);
    const selected = parseCommandReceiptStatus(value);
    if (selected) next.set("status", selected);
    else next.delete("status");
    setSearchParams(next);
  };
  const collectionParameters = new URLSearchParams(searchParams);
  collectionParameters.delete("itemsAfter");
  collectionParameters.delete("itemsTrail");
  const collectionHref = `/audit/command-receipts${collectionParameters.size > 0 ? `?${collectionParameters}` : ""}`;
  const error = commandId ? receipt.error : receipts.error;
  const errorMessage = error instanceof Error ? error.message : null;

  return (
    <>
      <div className="app-content-header">
        <div className="container-fluid">
          <nav aria-label="Breadcrumb">
            <ol className="breadcrumb mb-2">
              <li className="breadcrumb-item"><Link to="/projects">Projects</Link></li>
              {commandId ? <li className="breadcrumb-item"><Link to={collectionHref}>Command receipts</Link></li> : null}
              <li aria-current="page" className="breadcrumb-item active">{commandId ?? "Audit"}</li>
            </ol>
          </nav>
          <h1 className="mb-0" ref={headingRef} tabIndex={-1}>{commandId ? "Command receipt" : "Command receipts"}</h1>
        </div>
      </div>
      <div className="app-content">
        <div className="container-fluid vstack gap-4">
          <p className="text-body-secondary mb-0">
            Global command-completion audit facts are not inferred as belonging to any Project.
          </p>
          {commandId ? (
            <CommandReceiptDetailView
              backHref={collectionHref}
              errorMessage={errorMessage}
              loading={receipt.isPending}
              onRetry={() => { void receipt.refetch(); }}
              receipt={receipt.data?.commandReceipt ?? null}
            />
          ) : (
            <>
              <form className="card card-outline card-secondary" onSubmit={submitTool}>
                <div className="card-header"><h2 className="card-title">Filter receipts</h2></div>
                <div className="card-body row g-3 align-items-end">
                  <div className="col-12 col-lg">
                    <label className="form-label" htmlFor="receipt-tool">MCP tool name</label>
                    <input className="form-control" id="receipt-tool" onChange={(event) => setToolDraft(event.target.value)} placeholder="Exact tool name" value={toolDraft} />
                  </div>
                  <div className="col-12 col-sm-7 col-lg-3">
                    <label className="form-label" htmlFor="receipt-status">Status</label>
                    <select className="form-select" id="receipt-status" onChange={(event) => changeStatus(event.target.value)} value={status ?? ""}>
                      <option value="">All statuses</option>
                      {COMMAND_RECEIPT_STATUSES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
                    </select>
                  </div>
                  <div className="col-12 col-sm-5 col-lg-auto d-grid">
                    <button className="btn btn-primary" type="submit">Apply tool</button>
                  </div>
                </div>
              </form>
              <CommandReceiptListView
                canGoBack={searchParams.has("trail")}
                errorMessage={errorMessage}
                hasFilters={toolName.length > 0 || status !== undefined}
                loading={receipts.isPending}
                loadingRequestedPage={receipts.isPlaceholderData}
                onNext={() => {
                  const cursor = receipts.data?.commandReceipts.pageInfo.endCursor;
                  if (cursor) setSearchParams(nextReceiptPageParameters(searchParams, cursor));
                }}
                onPrevious={() => setSearchParams(previousReceiptPageParameters(searchParams))}
                onRetry={() => { void receipts.refetch(); }}
                page={receipts.data?.commandReceipts ?? null}
                pageNumber={pageNumber}
                receiptHref={(id) => `/audit/command-receipts/${encodeURIComponent(id)}${searchParams.size > 0 ? `?${searchParams}` : ""}`}
              />
            </>
          )}
        </div>
      </div>
    </>
  );
}
