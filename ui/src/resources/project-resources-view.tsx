import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { ContextLink as Link } from "../navigation.js";
import { DataTable, TextPreview, Timestamp } from "../data-table.js";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type {
  ProjectResource,
  ProjectResourceConnection,
  ResourceWorkIntention,
  ResourceWorkIntentionConnection
} from "./project-resources-model.js";
import { lifecycleBadgeClass, workIntentionBadgeClass } from "./project-resources-model.js";

export function useResourceHeading(title: string, focusKey: string): RefObject<HTMLHeadingElement> {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    document.title = `${title} · Coordinator`;
    headingRef.current?.focus();
  }, [focusKey, title]);
  return headingRef;
}


export function LoadingState({ label }: { readonly label: string }) {
  return (
    <div aria-live="polite" className="card" role="status">
      <div className="card-body d-flex align-items-center gap-3">
        <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
        <span>Loading {label}…</span>
      </div>
    </div>
  );
}

export function InitialError({ label, message, onRetry }: {
  readonly label: string;
  readonly message: string;
  readonly onRetry: () => void;
}) {
  return (
    <div className="alert alert-danger" role="alert">
      <h3 className="h5">{label} could not be loaded</h3>
      <p>{message}</p>
      <RetryRefresh announcementLabel={label} buttonClassName="btn btn-outline-light" onRetry={onRetry}>
        Retry
      </RetryRefresh>
    </div>
  );
}

export function AvailableStale({ message, onRetry }: {
  readonly message: string;
  readonly onRetry: () => void;
}) {
  return (
    <div className="alert alert-warning" role="alert">
      <p>The last available projection remains visible. {message}</p>
      <RetryRefresh
        announcementLabel="Resource view"
        buttonClassName="btn btn-outline-dark"
        onRetry={onRetry}
      >
        Retry refresh
      </RetryRefresh>
    </div>
  );
}

export function PaginationControls({ canPrevious, nextCursor, onNext, onPrevious }: {
  readonly canPrevious: boolean;
  readonly nextCursor: string | null;
  readonly onNext: (cursor: string) => void;
  readonly onPrevious: () => void;
}) {
  if (!canPrevious && !nextCursor) return null;
  return (
    <nav aria-label="Collection pages" className="d-flex justify-content-between gap-2">
      <button className="btn btn-outline-secondary" disabled={!canPrevious} onClick={onPrevious} type="button">
        Previous
      </button>
      <button
        className="btn btn-outline-primary"
        disabled={!nextCursor}
        onClick={() => nextCursor && onNext(nextCursor)}
        type="button"
      >
        Next
      </button>
    </nav>
  );
}

export function ResourceTable({ connection, hrefFor }: {
  readonly connection: ProjectResourceConnection;
  readonly hrefFor: (id: string) => string;
}) {
  return (
    <DataTable caption="Project resources" rows={connection.nodes} rowKey={(resource) => resource.id} emptyMessage="No Resources match these filters." columns={[
      { key: "path", label: "Path", render: (resource) => <><Link to={hrefFor(resource.id)}><code>{resource.path}</code></Link><div className="small text-body-secondary">{resource.id}</div></> },
      { key: "kind", label: "Kind", render: (resource) => resource.kind.toLowerCase() },
      { key: "status", label: "Status", render: (resource) => <span className={`badge ${lifecycleBadgeClass(resource.lifecycleStatus)}`}>{resource.lifecycleStatus.toLowerCase()}</span> },
      { key: "repository", label: "Repository", className: "d-none d-xl-table-cell", render: (resource) => <span className="small text-body-secondary">{resource.repositoryId}{resource.unbindingReason ? ` · ${resource.unbindingReason}` : ""}</span> },
      { key: "transition", label: "Last transition", render: (resource) => <Timestamp value={resource.lastTransitionAt} /> }
    ]} />
  );
}

export function WorkIntentionTable({ connection, hrefFor }: {
  readonly connection: ResourceWorkIntentionConnection;
  readonly hrefFor: (id: string) => string;
}) {
  return (
    <div>
      <DataTable caption="Active Resource work intentions" rows={connection.nodes} rowKey={(intention) => intention.id} emptyMessage="No active work intentions match these filters." columns={[
        { key: "resource", label: "Resource path", render: (intention) => <Link to={hrefFor(intention.id)}><code>{intention.resourcePath}</code></Link> },
        { key: "mode", label: "Mode", render: (intention) => <><span className={`badge ${intention.mode === "EXCLUSIVE" ? "text-bg-danger" : "text-bg-info"}`}>{intention.mode.toLowerCase()}</span><div className={`small badge ${workIntentionBadgeClass(intention.status)}`}>{intention.status.toLowerCase()}</div></> },
        { key: "agent", label: "Agent", render: (intention) => intention.agentId },
        { key: "purpose", label: "Purpose", render: (intention) => <><TextPreview text={intention.purpose} />{intention.context ? <div className="small text-body-secondary"><TextPreview text={intention.context} /></div> : null}</> },
        { key: "workItem", label: "Work item", render: (intention) => <><code>{intention.workItemId}</code><div className="small text-body-secondary">Attempt {intention.attemptId}</div></> },
        { key: "expires", label: "Expires", render: (intention) => <Timestamp value={intention.expiresAt} /> }
      ]} />
      <p className="small text-body-secondary mb-0">
        Active as of {formatted(connection.asOf)}. These are advisory intentions, not merge guarantees.
      </p>
    </div>
  );
}

export function ResourceDetail({ resource, backTo }: {
  readonly resource: ProjectResource;
  readonly backTo: string;
}) {
  return (
    <article className="card card-outline card-primary">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2">
        <h3 className="card-title text-break"><code>{resource.path}</code></h3>
        <span className={`badge ${lifecycleBadgeClass(resource.lifecycleStatus)}`}>
          {resource.lifecycleStatus.toLowerCase()}
        </span>
      </div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Resource path" value={resource.path} />
        <CopyIdentifier label="Resource ID" value={resource.id} />
        <DetailGroup title="Identity" rows={[
          ["Resource", resource.id],
          ["Repository", resource.repositoryId],
          ["Kind", resource.kind.toLowerCase()],
          ["Unbinding reason", resource.unbindingReason]
        ]} />
        <DetailGroup title="Registration" rows={[
          ["Actor", resource.registeredActorId],
          ["Event", resource.registeredEventId],
          ["Occurred", formatted(resource.registeredAt)]
        ]} />
        <DetailGroup title="Latest lifecycle transition" rows={[
          ["Actor", resource.latestTransitionActorId],
          ["Event", resource.latestTransitionEventId],
          ["Occurred", formatted(resource.lastTransitionAt)]
        ]} />
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to Resource inventory</Link>
      </div>
    </article>
  );
}

export function WorkIntentionDetail({ intention, backTo, projectPath }: {
  readonly intention: ResourceWorkIntention;
  readonly backTo: string;
  readonly projectPath: string;
}) {
  return (
    <article className="card card-outline card-warning">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2">
        <h3 className="card-title text-break"><code>{intention.resourcePath}</code></h3>
        <span className={`badge ${workIntentionBadgeClass(intention.status)}`}>
          {intention.status.toLowerCase()}
        </span>
      </div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Resource path" value={intention.resourcePath} />
        <CopyIdentifier label="Work-intention ID" value={intention.id} />
        <DetailGroup title="Purpose and accountability" rows={[
          ["Mode", intention.mode.toLowerCase()],
          ["Purpose", intention.purpose],
          ["Context", intention.context],
          ["Agent", intention.agentId],
          ["Attempt", intention.attemptId],
          ["WorkItem", intention.workItemId],
          ["ChangeSet", intention.changeSetId]
        ]} />
        <div className="d-flex flex-wrap gap-2">
          <Link className="btn btn-outline-primary" to={`${projectPath}/work-items/${encodeURIComponent(intention.workItemId)}`}>
            View WorkItem
          </Link>
          <Link className="btn btn-outline-primary" to={`${projectPath}/resources/${encodeURIComponent(intention.resourceId)}`}>
            View Resource
          </Link>
        </div>
        <DetailGroup title="Work intention" rows={[
          ["Intention", intention.id],
          ["Intention set", intention.intentionSetId],
          ["Fencing token", intention.fencingToken],
          ["Policy", intention.policyVersion],
          ["Declared", formatted(intention.declaredAt)],
          ["Expires", formatted(intention.expiresAt)],
          ["Withdrawn", formatted(intention.withdrawnAt)],
          ["Attempt terminal", formatted(intention.attemptTerminalAt)],
          ["Projection updated", formatted(intention.updatedAt)]
        ]} />
        <DetailGroup title="Event evidence" rows={[
          ["Declared event", intention.declaredEventId],
          ["Expanded event", intention.lastExpandedEventId],
          ["Renewed event", intention.lastRenewedEventId],
          ["Withdrawal event", intention.withdrawalEventId],
          ["Attempt terminal event", intention.attemptTerminalEventId]
        ]} />
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to active work intentions</Link>
      </div>
    </article>
  );
}

function DetailGroup({ title, rows }: {
  readonly title: string;
  readonly rows: ReadonlyArray<readonly [string, string | null | undefined]>;
}) {
  return (
    <section>
      <h4 className="h6 text-uppercase text-body-secondary">{title}</h4>
      <dl className="row mb-0">
        {rows.map(([label, value]) => (
          <div className="col-12 col-lg-6 mb-3" key={label}>
            <dt>{label}</dt>
            <dd className="text-break mb-0"><code>{value || "—"}</code></dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}
