import { ContextLink as Link } from "../navigation.js";
import { DataTable, Timestamp } from "../data-table.js";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type { OperationBatch, OperationBatchPage } from "./operation-batches-model.js";
import {
  batchStatusClass,
  formattedTimestamp,
  humanizedOperation
} from "./operation-batches-model.js";

interface AvailableStateProps {
  readonly errorMessage: string | null;
  readonly onRetry: () => void;
}

function AvailableState({ errorMessage, onRetry }: AvailableStateProps) {
  return errorMessage ? (
    <div className="alert alert-warning" role="alert">
      <h2 className="h5">Refresh failed</h2>
      <p>The last available operation facts remain visible. {errorMessage}</p>
      <RetryRefresh
        announcementLabel="Operation batches"
        buttonClassName="btn btn-outline-dark"
        onRetry={onRetry}
      >
        Retry refresh
      </RetryRefresh>
    </div>
  ) : null;
}

export interface OperationBatchListViewProps extends AvailableStateProps {
  readonly batchHref: (batchId: string) => string;
  readonly canGoBack: boolean;
  readonly hasFilters: boolean;
  readonly loading: boolean;
  readonly onNext: () => void;
  readonly onPrevious: () => void;
  readonly page: OperationBatchPage | null;
  readonly pageNumber: number;
  readonly loadingRequestedPage: boolean;
}

export function OperationBatchListView(props: OperationBatchListViewProps) {
  if (props.loading && !props.page) {
    return <div className="card"><div className="card-body" role="status">Loading operation batches…</div></div>;
  }
  if (props.errorMessage && !props.page) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5">Operation batches could not be loaded</h2>
        <p>{props.errorMessage}</p>
        <RetryRefresh
          announcementLabel="Operation batches"
          buttonClassName="btn btn-outline-light"
          onRetry={props.onRetry}
        >
          Retry
        </RetryRefresh>
      </div>
    );
  }
  if (!props.page || props.page.nodes.length === 0) {
    return (
      <div className="card">
        <div className="card-header"><h2 className="card-title">No operation batches</h2></div>
        <div className="card-body">
          {props.hasFilters
            ? "No global operation batches match the applied filters."
            : "No operation batches are available in the latest projection."}
        </div>
      </div>
    );
  }

  return (
    <section aria-labelledby="operation-batches-heading" className="vstack gap-3">
      <AvailableState errorMessage={props.errorMessage} onRetry={props.onRetry} />
      <div className="d-flex flex-wrap align-items-center justify-content-between gap-2">
        <div>
          <h2 className="h4 mb-1" id="operation-batches-heading">Available batches</h2>
          <p className="small text-body-secondary mb-0">Page {props.pageNumber} · {props.page.nodes.length} on this page</p>
        </div>
        <span
          aria-atomic="true"
          aria-live="polite"
          className="small text-body-secondary"
        >
          {props.loadingRequestedPage ? "Loading the requested page…" : "\u00a0"}
        </span>
      </div>
      <DataTable caption="Operation batches" rows={props.page.nodes} rowKey={(batch) => batch.id} columns={[
        { key: "operation", label: "Operation", render: (batch) => <><Link aria-label={`Open batch ${batch.id}`} className="fw-semibold" to={props.batchHref(batch.id)}>{humanizedOperation(batch.targetTool)}</Link><div className="small text-body-secondary">{batch.id}</div></> },
        { key: "status", label: "Status", render: (batch) => <span className={`badge ${batchStatusClass(batch.status)}`}>{humanizedOperation(batch.status)}</span> },
        { key: "total", label: "Items", render: (batch) => batch.total },
        { key: "succeeded", label: "Succeeded", render: (batch) => batch.succeeded },
        { key: "pending", label: "Pending", render: (batch) => batch.pending },
        { key: "other", label: "Rejected / not run", render: (batch) => `${batch.rejected} / ${batch.notRun}` },
        { key: "created", label: "Created", render: (batch) => <Timestamp value={batch.createdAt} /> }
      ]} />
      <nav aria-label="Operation batch pagination" className="d-flex justify-content-between gap-3">
        <button className="btn btn-outline-secondary" disabled={!props.canGoBack} onClick={props.onPrevious} type="button">Previous page</button>
        <button className="btn btn-outline-primary" disabled={!props.page.pageInfo.hasNextPage} onClick={props.onNext} type="button">Next page</button>
      </nav>
    </section>
  );
}

export interface OperationBatchDetailViewProps extends AvailableStateProps {
  readonly backHref: string;
  readonly batch: OperationBatch | null;
  readonly canGoBack: boolean;
  readonly loading: boolean;
  readonly onNext: () => void;
  readonly onPrevious: () => void;
  readonly pageNumber: number;
  readonly loadingRequestedPage: boolean;
}

export function OperationBatchDetailView(props: OperationBatchDetailViewProps) {
  if (props.loading && !props.batch) {
    return <div className="card"><div className="card-body" role="status">Loading operation batch…</div></div>;
  }
  if (props.errorMessage && !props.batch) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5">Operation batch could not be loaded</h2>
        <p>{props.errorMessage}</p>
        <div className="d-flex flex-wrap gap-2">
          <RetryRefresh
            announcementLabel="Operation batch"
            buttonClassName="btn btn-outline-light"
            onRetry={props.onRetry}
          >
            Retry
          </RetryRefresh>
          <Link className="btn btn-outline-light" to={props.backHref}>Back to batches</Link>
        </div>
      </div>
    );
  }
  if (!props.batch) {
    return (
      <div className="alert alert-warning" role="status">
        <h2 className="h5">Batch is not available</h2>
        <p>No latest available operation-batch fact matches this batch ID.</p>
        <Link className="btn btn-outline-dark" to={props.backHref}>Back to batches</Link>
      </div>
    );
  }

  const { batch, items } = props.batch;
  return (
    <div className="vstack gap-3">
      <AvailableState errorMessage={props.errorMessage} onRetry={props.onRetry} />
      <article className="card card-outline card-dark">
        <div className="card-header d-flex flex-wrap align-items-start justify-content-between gap-2">
          <div>
            <h2 className="card-title fw-semibold mb-1">{humanizedOperation(batch.targetTool)}</h2>
            <div className="mt-2"><CopyIdentifier label="Operation batch ID" value={batch.id} /></div>
          </div>
          <span className={`badge ${batchStatusClass(batch.status)}`}>{humanizedOperation(batch.status)}</span>
        </div>
        <div className="card-body vstack gap-4">
          <div className="row row-cols-2 row-cols-lg-5 g-3">
            <div><div className="fs-4 fw-semibold">{batch.total}</div><div className="small text-body-secondary">Total</div></div>
            <div><div className="fs-4 fw-semibold">{batch.succeeded}</div><div className="small text-body-secondary">Succeeded</div></div>
            <div><div className="fs-4 fw-semibold">{batch.rejected}</div><div className="small text-body-secondary">Rejected</div></div>
            <div><div className="fs-4 fw-semibold">{batch.pending}</div><div className="small text-body-secondary">Pending</div></div>
            <div><div className="fs-4 fw-semibold">{batch.notRun}</div><div className="small text-body-secondary">Not run</div></div>
          </div>
          <dl className="row mb-0">
            <dt className="col-sm-3">Created</dt><dd className="col-sm-9"><time dateTime={batch.createdAt}>{formattedTimestamp(batch.createdAt)}</time></dd>
            <dt className="col-sm-3">Manifest</dt><dd className="col-sm-9"><CopyIdentifier label="Manifest digest" value={batch.manifestDigest} /></dd>
          </dl>
          <section aria-labelledby="batch-items-heading" className="vstack gap-3">
            <div>
              <h3 className="h5 mb-1" id="batch-items-heading">Batch items</h3>
              <p className="small text-body-secondary mb-0">Page {props.pageNumber}</p>
            </div>
            <span
              aria-atomic="true"
              aria-live="polite"
              className="small text-body-secondary"
            >
              {props.loadingRequestedPage ? "Loading the requested item page…" : "\u00a0"}
            </span>
            {items.nodes.length === 0 ? (
              <p className="text-body-secondary mb-0">No item outcomes are available on this page.</p>
            ) : (
              <DataTable caption="Batch items" rows={items.nodes} rowKey={(item) => String(item.index)} columns={[
                { key: "item", label: "Item", render: (item) => <><strong>Item {item.index}</strong><div className="small">{humanizedOperation(item.targetTool)}</div></> },
                { key: "command", label: "Command ID", render: (item) => <code>{item.commandId}</code> },
                { key: "status", label: "Status", render: (item) => <span className={`badge ${batchStatusClass(item.status)}`}>{humanizedOperation(item.status)}</span> },
                { key: "outcome", label: "Outcome", render: (item) => <>{item.outcomeSummary ?? "No terminal outcome has been observed."}{item.outcomeCode ? <div className="small text-body-secondary">{item.outcomeCode}</div> : null}</> },
                { key: "finished", label: "Finished", render: (item) => <Timestamp value={item.finishedAt} /> }
              ]} />
            )}
            <nav aria-label="Operation batch item pagination" className="d-flex justify-content-between gap-3">
              <button className="btn btn-outline-secondary" disabled={!props.canGoBack} onClick={props.onPrevious} type="button">Previous page</button>
              <button className="btn btn-outline-primary" disabled={!items.pageInfo.hasNextPage} onClick={props.onNext} type="button">Next page</button>
            </nav>
          </section>
        </div>
        <div className="card-footer"><Link className="btn btn-outline-secondary" to={props.backHref}><i aria-hidden="true" className="bi bi-arrow-left me-1" /> Back to batches</Link></div>
      </article>
    </div>
  );
}
