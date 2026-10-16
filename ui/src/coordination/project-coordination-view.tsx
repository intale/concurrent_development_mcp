import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { ContextLink as Link } from "../navigation.js";
import { DataTable, TextPreview, Timestamp } from "../data-table.js";
import { CopyIdentifier } from "../copy-identifier.js";
import type { CoordinationPresentationStatus } from "../gql/graphql.js";
import { RetryRefresh } from "../retry-refresh.js";
import type {
  CoordinationChangeSet,
  CoordinationDependency,
  CoordinationWorkItem,
  CoordinationWorkItemDetail
} from "./project-coordination-model.js";
import { statusBadgeClass } from "./project-coordination-model.js";

export function useCoordinationHeading(title: string, focusKey: string): RefObject<HTMLHeadingElement> {
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
        announcementLabel="Coordination view"
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
      <button className="btn btn-outline-primary" disabled={!nextCursor} onClick={() => nextCursor && onNext(nextCursor)} type="button">
        Next
      </button>
    </nav>
  );
}

export function ChangeSetTable({ items, hrefFor }: {
  readonly items: readonly CoordinationChangeSet[];
  readonly hrefFor: (id: string) => string;
}) {
  if (items.length === 0) return <div className="alert alert-info" role="status">No ChangeSets are available.</div>;
  return (
    <DataTable caption="ChangeSets" rows={items} rowKey={(item) => item.id} columns={[
      { key: "goal", label: "Change set", render: (item) => <><Link aria-label={`View ChangeSet ${item.id}`} className="fw-semibold" to={hrefFor(item.id)}><TextPreview text={item.goal} /></Link><div className="small text-body-secondary">{item.id}</div></> },
      { key: "status", label: "Status", render: (item) => <span className={`badge ${item.domainStatus === "completed" ? "text-bg-success" : "text-bg-secondary"}`}>{item.domainStatus}</span> },
      { key: "work", label: "Work items", render: (item) => `${item.runningWorkItemCount} running · ${item.openWorkItemCount} open · ${item.workItemCount} total` },
      { key: "updated", label: "Updated", render: (item) => <Timestamp value={item.lastProcessedAt} /> }
    ]} />
  );
}

function StatusBadge({ status }: { readonly status: CoordinationPresentationStatus }) {
  return <span className={`badge ${statusBadgeClass(status)}`}>{status.toLowerCase()}</span>;
}

export function WorkItemTable({ items, hrefFor }: {
  readonly items: readonly CoordinationWorkItem[];
  readonly hrefFor: (id: string) => string;
}) {
  if (items.length === 0) return <div className="alert alert-info" role="status">No WorkItems match these filters.</div>;
  return (
    <DataTable caption="Scheduled WorkItems" rows={items} rowKey={(item) => item.id} columns={[
      { key: "goal", label: "Work item", render: (item) => <><Link aria-label={`View WorkItem ${item.id}`} className="fw-semibold" to={hrefFor(item.id)}><TextPreview text={item.goal} /></Link><div className="small text-body-secondary">{item.id}</div></> },
      { key: "status", label: "Status", render: (item) => <StatusBadge status={item.presentationStatus} /> },
      { key: "agent", label: "Agent", render: (item) => item.activeAgentId ?? "Unassigned" },
      { key: "attempt", label: "Attempt", className: "d-none d-xl-table-cell text-nowrap", render: (item) => item.attemptStatus ?? "Not started" },
      { key: "state", label: "Domain state", className: "d-none d-xl-table-cell text-nowrap", render: (item) => item.domainStatus },
      { key: "updated", label: "Updated", render: (item) => <Timestamp value={item.lastProcessedAt} /> }
    ]} />
  );
}

export function DependencyTable({ items, hrefFor }: {
  readonly items: readonly CoordinationDependency[];
  readonly hrefFor: (id: string) => string;
}) {
  if (items.length === 0) return <div className="alert alert-info" role="status">No dependencies match this state.</div>;
  return (
    <DataTable caption="WorkItem dependencies" rows={items} rowKey={(item) => item.id} columns={[
      { key: "kind", label: "Dependency", render: (item) => <><Link aria-label={`View dependency ${item.id}`} to={hrefFor(item.id)}>{item.dependencyKind.replaceAll("_", " ")}</Link><div className="small text-body-secondary">{item.id}</div></> },
      { key: "state", label: "State", render: (item) => <span className={`badge ${item.blocking ? "text-bg-warning" : "text-bg-success"}`}>{item.blocking ? "blocking" : "satisfied"}</span> },
      { key: "producer", label: "Producer", render: (item) => <span className="small">{item.producerWorkItemId}</span> },
      { key: "consumer", label: "Consumer", render: (item) => <span className="small">{item.consumerWorkItemId}</span> },
      { key: "updated", label: "Updated", render: (item) => <Timestamp value={item.lastProcessedAt} /> }
    ]} />
  );
}

export function ChangeSetDetail({ item }: { readonly item: CoordinationChangeSet }) {
  return (
    <article className="card card-outline card-primary">
      <div className="card-body vstack gap-3">
        <div className="d-flex flex-wrap justify-content-between gap-2">
          <h3 className="h4 mb-0">{item.goal}</h3>
          <span className="badge text-bg-secondary">{item.domainStatus}</span>
        </div>
        <CopyIdentifier label="ChangeSet ID" value={item.id} />
        <div>{item.runningWorkItemCount} running · {item.openWorkItemCount} open · {item.workItemCount} total</div>
        <section aria-labelledby="change-set-criteria"><h4 className="h5" id="change-set-criteria">Acceptance criteria</h4><ul className="mb-0">{item.acceptanceCriteria.map((criterion) => <li key={criterion}>{criterion}</li>)}</ul></section>
        <p className="small text-body-secondary mb-0">Last projected {formatted(item.lastProcessedAt)}</p>
      </div>
    </article>
  );
}

export function WorkItemDetail({ detail }: { readonly detail: CoordinationWorkItemDetail }) {
  const { workItem, attempt, checkpoint } = detail;
  return (
    <div className="vstack gap-3">
      <article className="card card-outline card-primary"><div className="card-body vstack gap-2">
        <div className="d-flex flex-wrap justify-content-between gap-2"><h3 className="h4 mb-0">{workItem.goal}</h3><StatusBadge status={workItem.presentationStatus} /></div>
        <CopyIdentifier label="WorkItem ID" value={workItem.id} />
        <div><strong>Domain state:</strong> {workItem.domainStatus}</div>
        <div><strong>ChangeSet:</strong> <code className="text-break">{workItem.changeSetId}</code></div>
        <section aria-labelledby="work-item-criteria"><h4 className="h5" id="work-item-criteria">Acceptance criteria</h4><ul className="mb-0">{workItem.acceptanceCriteria.map((criterion) => <li key={criterion}>{criterion}</li>)}</ul></section>
      </div></article>
      <section className="card" aria-labelledby="attempt-heading"><div className="card-header"><h3 className="card-title" id="attempt-heading">Current or latest Attempt</h3></div><div className="card-body">
        {attempt ? <div className="vstack gap-2"><div><strong>Agent:</strong> {attempt.agentId}</div><div><strong>Status:</strong> {attempt.status}</div><CopyIdentifier label="Attempt ID" value={attempt.id} /><div className="small text-body-secondary">Authorized {formatted(attempt.authorizedAt)}</div>{attempt.abandonmentReason ? <div className="alert alert-warning mb-0">{attempt.abandonmentReason}</div> : null}</div> : <p className="mb-0">No Attempt has been projected.</p>}
      </div></section>
      <section className="card" aria-labelledby="checkpoint-heading"><div className="card-header"><h3 className="card-title" id="checkpoint-heading">Latest checkpoint</h3></div><div className="card-body">
        {checkpoint ? <div className="vstack gap-2"><div><strong>Kind:</strong> {checkpoint.checkpointKind}</div><div><strong>Evidence:</strong> {checkpoint.evidenceStatus}</div><div><strong>Branch:</strong> {checkpoint.targetBranch}</div><CopyIdentifier label="Candidate checkpoint ID" value={checkpoint.id} /><CopyIdentifier label="Head commit" value={checkpoint.headCommitOid} /></div> : <p className="mb-0">No Candidate checkpoint has been projected.</p>}
      </div></section>
    </div>
  );
}

export function DependencyDetail({ item }: { readonly item: CoordinationDependency }) {
  return (
    <article className={`card card-outline ${item.blocking ? "card-warning" : "card-success"}`}>
      <div className="card-body vstack gap-3">
        <div className="d-flex flex-wrap justify-content-between gap-2"><h3 className="h4 mb-0">{item.dependencyKind.replaceAll("_", " ")}</h3><span className={`badge ${item.blocking ? "text-bg-warning" : "text-bg-success"}`}>{item.blocking ? "blocking" : "satisfied"}</span></div>
        <CopyIdentifier label="Dependency ID" value={item.id} />
        <div><strong>Producer WorkItem:</strong> <code className="text-break">{item.producerWorkItemId}</code></div>
        <div><strong>Consumer WorkItem:</strong> <code className="text-break">{item.consumerWorkItemId}</code></div>
        {item.requiredOutput ? <div><strong>Required output:</strong> {item.requiredOutput.kind} · <code>{item.requiredOutput.key}</code></div> : null}
        <div className="small text-body-secondary">Declared {formatted(item.declaredAt)}{item.satisfiedAt ? ` · satisfied ${formatted(item.satisfiedAt)}` : ""}</div>
      </div>
    </article>
  );
}

function formatted(value: string): string {
  return new Date(value).toLocaleString();
}
