import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { Link, NavLink } from "react-router-dom";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type {
  ProjectResource,
  ProjectResourceConnection,
  ResourceLease,
  ResourceLeaseConnection
} from "./project-resources-model.js";
import { leaseBadgeClass, lifecycleBadgeClass } from "./project-resources-model.js";

export function useResourceHeading(title: string, focusKey: string): RefObject<HTMLHeadingElement> {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    document.title = `${title} · Coordinator`;
    headingRef.current?.focus();
  }, [focusKey, title]);
  return headingRef;
}

export function ResourceNavigation({ basePath }: { readonly basePath: string }) {
  const navClassName = ({ isActive }: { readonly isActive: boolean }) => `nav-link${isActive ? " active" : ""}`;
  return (
    <nav aria-label="Resource views" className="mb-3">
      <ul className="nav nav-pills flex-column flex-sm-row gap-2">
        <li className="nav-item">
          <NavLink className={navClassName} to={`${basePath}/inventory`}>Resource inventory</NavLink>
        </li>
        <li className="nav-item">
          <NavLink className={navClassName} to={`${basePath}/leases`}>Active leases</NavLink>
        </li>
      </ul>
    </nav>
  );
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

export function ResourceCards({ connection, hrefFor }: {
  readonly connection: ProjectResourceConnection;
  readonly hrefFor: (id: string) => string;
}) {
  if (connection.nodes.length === 0) {
    return <div className="alert alert-info" role="status">No Resources match these filters.</div>;
  }
  return (
    <div aria-label="Project resources" className="row g-3">
      {connection.nodes.map((resource) => (
        <div className="col-12 col-xl-6" key={resource.id}>
          <article className="card card-outline card-primary h-100">
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2">
                <h3 className="h5 text-break mb-0"><code>{resource.path}</code></h3>
                <span className={`badge ${lifecycleBadgeClass(resource.lifecycleStatus)}`}>
                  {resource.lifecycleStatus.toLowerCase()}
                </span>
              </div>
              <div>{resource.kind.toLowerCase()}</div>
              {resource.unbindingReason ? <div><strong>Reason:</strong> {resource.unbindingReason}</div> : null}
              <div className="small text-body-secondary text-break">Repository {resource.repositoryId}</div>
              <Link className="btn btn-primary align-self-start mt-auto" to={hrefFor(resource.id)}>
                View Resource
              </Link>
            </div>
          </article>
        </div>
      ))}
    </div>
  );
}

export function LeaseCards({ connection, hrefFor }: {
  readonly connection: ResourceLeaseConnection;
  readonly hrefFor: (id: string) => string;
}) {
  if (connection.nodes.length === 0) {
    return <div className="alert alert-info" role="status">No active lease facts match these filters.</div>;
  }
  return (
    <div aria-label="Active resource leases" className="row g-3">
      {connection.nodes.map((lease) => (
        <div className="col-12 col-xl-6" key={lease.id}>
          <article className="card card-outline card-warning h-100">
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2">
                <h3 className="h5 text-break mb-0"><code>{lease.resourcePath}</code></h3>
                <span className={`badge ${leaseBadgeClass(lease.status)}`}>{lease.status.toLowerCase()}</span>
              </div>
              <div><strong>Holder:</strong> {lease.agentId}</div>
              <div><strong>WorkItem:</strong> <code className="text-break">{lease.workItemId}</code></div>
              <div className="small text-body-secondary text-break">Attempt {lease.attemptId}</div>
              <Link className="btn btn-warning align-self-start mt-auto" to={hrefFor(lease.id)}>
                View lease
              </Link>
            </div>
          </article>
        </div>
      ))}
      <p className="small text-body-secondary mb-0">
        Active as of {formatted(connection.asOf)}. Ownership comes only from projected lease facts.
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

export function LeaseDetail({ lease, backTo, projectPath }: {
  readonly lease: ResourceLease;
  readonly backTo: string;
  readonly projectPath: string;
}) {
  return (
    <article className="card card-outline card-warning">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2">
        <h3 className="card-title text-break"><code>{lease.resourcePath}</code></h3>
        <span className={`badge ${leaseBadgeClass(lease.status)}`}>{lease.status.toLowerCase()}</span>
      </div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Resource path" value={lease.resourcePath} />
        <CopyIdentifier label="Lease ID" value={lease.id} />
        <DetailGroup title="Holder" rows={[
          ["Agent", lease.agentId],
          ["Attempt", lease.attemptId],
          ["WorkItem", lease.workItemId],
          ["ChangeSet", lease.changeSetId]
        ]} />
        <div className="d-flex flex-wrap gap-2">
          <Link className="btn btn-outline-primary" to={`${projectPath}/coordination/work-items/${encodeURIComponent(lease.workItemId)}`}>
            View WorkItem
          </Link>
          <Link className="btn btn-outline-primary" to={`${projectPath}/resources/inventory/${encodeURIComponent(lease.resourceId)}`}>
            View Resource
          </Link>
        </div>
        <DetailGroup title="Lease" rows={[
          ["Lease", lease.id],
          ["Lease set", lease.leaseSetId],
          ["Fencing token", lease.fencingToken],
          ["Policy", lease.policyVersion],
          ["Reserved", formatted(lease.reservedAt)],
          ["Expires", formatted(lease.expiresAt)],
          ["Released", formatted(lease.releasedAt)],
          ["Attempt terminal", formatted(lease.attemptTerminalAt)]
        ]} />
        <DetailGroup title="Event evidence" rows={[
          ["Reserved event", lease.reservedEventId],
          ["Expanded event", lease.lastExpandedEventId],
          ["Renewed event", lease.lastRenewedEventId],
          ["Release event", lease.releaseEventId],
          ["Attempt terminal event", lease.attemptTerminalEventId]
        ]} />
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to active leases</Link>
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
