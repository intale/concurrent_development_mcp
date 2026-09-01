import { Link } from "react-router-dom";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type { CommandReceipt, CommandReceiptPage } from "./command-receipts-model.js";
import { formattedTimestamp } from "./command-receipts-model.js";

interface AvailableStateProps {
  readonly errorMessage: string | null;
  readonly onRetry: () => void;
}

function AvailableState({ errorMessage, onRetry }: AvailableStateProps) {
  return errorMessage ? (
    <div className="alert alert-warning" role="alert">
      <h2 className="h5">Refresh failed</h2>
      <p>The last available audit facts remain visible. {errorMessage}</p>
      <RetryRefresh
        announcementLabel="Command receipts"
        buttonClassName="btn btn-outline-dark"
        onRetry={onRetry}
      >
        Retry refresh
      </RetryRefresh>
    </div>
  ) : null;
}

export interface CommandReceiptListViewProps extends AvailableStateProps {
  readonly canGoBack: boolean;
  readonly hasFilters: boolean;
  readonly loading: boolean;
  readonly onNext: () => void;
  readonly onPrevious: () => void;
  readonly page: CommandReceiptPage | null;
  readonly pageNumber: number;
  readonly loadingRequestedPage: boolean;
  readonly receiptHref: (commandId: string) => string;
}

export function CommandReceiptListView(props: CommandReceiptListViewProps) {
  if (props.loading && !props.page) {
    return (
      <div aria-live="polite" className="card" role="status">
        <div className="card-body d-flex align-items-center gap-3">
          <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
          <span>Loading command receipts…</span>
        </div>
      </div>
    );
  }

  if (props.errorMessage && !props.page) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5">Command receipts could not be loaded</h2>
        <p>{props.errorMessage}</p>
        <RetryRefresh
          announcementLabel="Command receipts"
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
        <div className="card-header"><h2 className="card-title">No command receipts</h2></div>
        <div className="card-body">
          {props.hasFilters
            ? "No global command-completion facts match the applied filters."
            : "No command-completion facts are available in the latest projection."}
        </div>
      </div>
    );
  }

  return (
    <section aria-labelledby="command-receipts-heading" className="vstack gap-3">
      <AvailableState errorMessage={props.errorMessage} onRetry={props.onRetry} />
      <div className="d-flex flex-wrap align-items-center justify-content-between gap-2">
        <div>
          <h2 className="h4 mb-1" id="command-receipts-heading">Available receipts</h2>
          <p className="small text-body-secondary mb-0">
            Page {props.pageNumber} · {props.page.nodes.length} on this page
          </p>
        </div>
        <span
          aria-atomic="true"
          aria-live="polite"
          className="small text-body-secondary"
        >
          {props.loadingRequestedPage ? "Loading the requested page…" : "\u00a0"}
        </span>
      </div>
      <div className="row row-cols-1 row-cols-xl-2 g-3">
        {props.page.nodes.map((receipt) => (
          <div className="col" key={receipt.commandId}>
            <article className="card card-outline card-secondary h-100">
              <div className="card-header">
                <div className="d-flex align-items-start justify-content-between gap-2">
                  <h3 className="card-title fw-semibold text-break mb-1">{receipt.toolName}</h3>
                  <span className="badge text-bg-success flex-shrink-0">{receipt.status.toLowerCase()}</span>
                </div>
                <div className="small text-body-secondary text-break w-100"><code>{receipt.commandId}</code></div>
              </div>
              <div className="card-body vstack gap-2">
                <p className="mb-0">{receipt.summary}</p>
                <div className="small text-body-secondary">
                  Completed <time dateTime={receipt.completedAt}>{formattedTimestamp(receipt.completedAt)}</time>
                </div>
                <div className="small">
                  {receipt.emittedEvents.length} emitted {receipt.emittedEvents.length === 1 ? "event" : "events"}
                  {receipt.warnings.length > 0 ? ` · ${receipt.warnings.length} warnings` : ""}
                </div>
              </div>
              <div className="card-footer d-grid">
                <Link className="btn btn-primary" to={props.receiptHref(receipt.commandId)}>
                  Open receipt <i aria-hidden="true" className="bi bi-arrow-right ms-1" />
                </Link>
              </div>
            </article>
          </div>
        ))}
      </div>
      <nav aria-label="Command receipt pagination" className="d-flex justify-content-between gap-3">
        <button className="btn btn-outline-secondary" disabled={!props.canGoBack} onClick={props.onPrevious} type="button">
          Previous page
        </button>
        <button className="btn btn-outline-primary" disabled={!props.page.pageInfo.hasNextPage} onClick={props.onNext} type="button">
          Next page
        </button>
      </nav>
    </section>
  );
}

export interface CommandReceiptDetailViewProps extends AvailableStateProps {
  readonly backHref: string;
  readonly loading: boolean;
  readonly receipt: CommandReceipt | null;
}

export function CommandReceiptDetailView(props: CommandReceiptDetailViewProps) {
  if (props.loading && !props.receipt) {
    return <div className="card"><div className="card-body" role="status">Loading command receipt…</div></div>;
  }

  if (props.errorMessage && !props.receipt) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5">Command receipt could not be loaded</h2>
        <p>{props.errorMessage}</p>
        <div className="d-flex flex-wrap gap-2">
          <RetryRefresh
            announcementLabel="Command receipt"
            buttonClassName="btn btn-outline-light"
            onRetry={props.onRetry}
          >
            Retry
          </RetryRefresh>
          <Link className="btn btn-outline-light" to={props.backHref}>Back to receipts</Link>
        </div>
      </div>
    );
  }

  if (!props.receipt) {
    return (
      <div className="alert alert-warning" role="status">
        <h2 className="h5">Receipt is not available</h2>
        <p>No latest available command-completion fact matches this command ID.</p>
        <Link className="btn btn-outline-dark" to={props.backHref}>Back to receipts</Link>
      </div>
    );
  }

  const receipt = props.receipt;
  return (
    <div className="vstack gap-3">
      <AvailableState errorMessage={props.errorMessage} onRetry={props.onRetry} />
      <article className="card card-outline card-secondary">
        <div className="card-header d-flex flex-wrap justify-content-between gap-2">
          <div>
            <h2 className="card-title fw-semibold mb-1">{receipt.toolName}</h2>
            <div className="mt-2"><CopyIdentifier label="Command ID" value={receipt.commandId} /></div>
          </div>
          <span className="badge text-bg-success align-self-start">{receipt.status.toLowerCase()}</span>
        </div>
        <div className="card-body vstack gap-4">
          <p className="fs-5 mb-0">{receipt.summary}</p>
          <dl className="row mb-0">
            <dt className="col-sm-3">Receipt</dt><dd className="col-sm-9"><CopyIdentifier label="Receipt ID" value={receipt.receipt} /></dd>
            <dt className="col-sm-3">Completed</dt><dd className="col-sm-9"><time dateTime={receipt.completedAt}>{formattedTimestamp(receipt.completedAt)}</time></dd>
            <dt className="col-sm-3">Next tools</dt><dd className="col-sm-9">{receipt.nextActionTools.join(", ") || "None"}</dd>
            <dt className="col-sm-3">Warnings</dt><dd className="col-sm-9">{receipt.warnings.join(" · ") || "None"}</dd>
          </dl>
          <section aria-labelledby="receipt-events-heading">
            <h3 className="h5" id="receipt-events-heading">Emitted event facts</h3>
            {receipt.emittedEvents.length === 0 ? (
              <p className="text-body-secondary mb-0">No emitted events were recorded.</p>
            ) : (
              <div className="list-group">
                {receipt.emittedEvents.map((event) => (
                  <div className="list-group-item" key={event.id}>
                    <div className="d-flex flex-wrap justify-content-between gap-2">
                      <strong>{event.type}</strong><span>revision {event.streamRevision}</span>
                    </div>
                    <div className="text-break"><code>{event.streamContext}/{event.streamName}/{event.streamId}</code></div>
                    <div className="small text-body-secondary text-break">{event.id}</div>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
        <div className="card-footer">
          <Link className="btn btn-outline-secondary" to={props.backHref}>
            <i aria-hidden="true" className="bi bi-arrow-left me-1" /> Back to receipts
          </Link>
        </div>
      </article>
    </div>
  );
}
