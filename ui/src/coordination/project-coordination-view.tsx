import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { Link, NavLink } from "react-router-dom";
import type { CoordinationPresentationStatus } from "../gql/graphql.js";
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

export function CoordinationNavigation({ basePath }: { readonly basePath: string }) {
  const navClassName = ({ isActive }: { readonly isActive: boolean }) => `nav-link${isActive ? " active" : ""}`;

  return (
    <nav aria-label="Coordination views" className="mb-3">
      <ul className="nav nav-pills flex-column flex-sm-row gap-2">
        <li className="nav-item"><NavLink className={navClassName} to={`${basePath}/change-sets`}>ChangeSets</NavLink></li>
        <li className="nav-item"><NavLink className={navClassName} to={`${basePath}/work-items`}>WorkItems</NavLink></li>
        <li className="nav-item"><NavLink className={navClassName} to={`${basePath}/dependencies`}>Dependencies</NavLink></li>
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
      <h2 className="h5">{label} could not be loaded</h2>
      <p>{message}</p>
      <button className="btn btn-outline-light btn-sm" onClick={onRetry} type="button">Retry</button>
    </div>
  );
}

export function AvailableStale({ message, onRetry }: {
  readonly message: string;
  readonly onRetry: () => void;
}) {
  return (
    <div className="alert alert-warning" role="alert">
      The last available projection remains visible. {message}
      <button className="btn btn-outline-dark btn-sm ms-3" onClick={onRetry} type="button">Retry refresh</button>
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

export function ChangeSetCards({ items, hrefFor }: {
  readonly items: readonly CoordinationChangeSet[];
  readonly hrefFor: (id: string) => string;
}) {
  if (items.length === 0) return <div className="alert alert-info" role="status">No ChangeSets are available.</div>;
  return (
    <div aria-label="ChangeSets" className="row g-3">
      {items.map((item) => (
        <div className="col-12 col-xl-6" key={item.id}>
          <article className="card h-100 card-outline card-primary">
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2">
                <h3 className="h5 mb-0">{item.goal}</h3>
                <span className="badge text-bg-secondary">{item.domainStatus}</span>
              </div>
              <div className="small text-body-secondary">
                {item.runningWorkItemCount} running · {item.openWorkItemCount} open · {item.workItemCount} total
              </div>
              <code className="small text-break">{item.id}</code>
              <Link className="btn btn-primary align-self-start mt-auto" to={hrefFor(item.id)}>View ChangeSet</Link>
            </div>
          </article>
        </div>
      ))}
    </div>
  );
}

function StatusBadge({ status }: { readonly status: CoordinationPresentationStatus }) {
  return <span className={`badge ${statusBadgeClass(status)}`}>{status.toLowerCase()}</span>;
}

export function WorkItemCards({ items, hrefFor }: {
  readonly items: readonly CoordinationWorkItem[];
  readonly hrefFor: (id: string) => string;
}) {
  if (items.length === 0) return <div className="alert alert-info" role="status">No WorkItems match these filters.</div>;
  return (
    <div aria-label="Scheduled WorkItems" className="row g-3">
      {items.map((item) => (
        <div className="col-12 col-xl-6" key={item.id}>
          <article className="card h-100 card-outline card-primary">
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2">
                <h3 className="h5 mb-0">{item.goal}</h3>
                <StatusBadge status={item.presentationStatus} />
              </div>
              <div><strong>Agent:</strong> {item.activeAgentId ?? "Unassigned"}</div>
              {item.attemptStatus ? <div><strong>Attempt:</strong> {item.attemptStatus}</div> : null}
              <div className="small text-body-secondary">Domain state: {item.domainStatus}</div>
              <code className="small text-break">{item.id}</code>
              <Link className="btn btn-primary align-self-start mt-auto" to={hrefFor(item.id)}>View WorkItem</Link>
            </div>
          </article>
        </div>
      ))}
    </div>
  );
}

export function DependencyCards({ items, hrefFor }: {
  readonly items: readonly CoordinationDependency[];
  readonly hrefFor: (id: string) => string;
}) {
  if (items.length === 0) return <div className="alert alert-info" role="status">No dependencies match this state.</div>;
  return (
    <div aria-label="WorkItem dependencies" className="row g-3">
      {items.map((item) => (
        <div className="col-12 col-xl-6" key={item.id}>
          <article className={`card h-100 card-outline ${item.blocking ? "card-warning" : "card-success"}`}>
            <div className="card-body d-flex flex-column gap-2">
              <div className="d-flex flex-wrap justify-content-between gap-2">
                <h3 className="h5 mb-0">{item.dependencyKind.replaceAll("_", " ")}</h3>
                <span className={`badge ${item.blocking ? "text-bg-warning" : "text-bg-success"}`}>
                  {item.blocking ? "blocking" : "satisfied"}
                </span>
              </div>
              <div><strong>Producer:</strong> <code className="text-break">{item.producerWorkItemId}</code></div>
              <div><strong>Consumer:</strong> <code className="text-break">{item.consumerWorkItemId}</code></div>
              <code className="small text-body-secondary text-break">{item.id}</code>
              <Link className="btn btn-primary align-self-start mt-auto" to={hrefFor(item.id)}>View dependency</Link>
            </div>
          </article>
        </div>
      ))}
    </div>
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
        <code className="text-break">{item.id}</code>
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
        <code className="text-break">{workItem.id}</code>
        <div><strong>Domain state:</strong> {workItem.domainStatus}</div>
        <div><strong>ChangeSet:</strong> <code className="text-break">{workItem.changeSetId}</code></div>
        <section aria-labelledby="work-item-criteria"><h4 className="h5" id="work-item-criteria">Acceptance criteria</h4><ul className="mb-0">{workItem.acceptanceCriteria.map((criterion) => <li key={criterion}>{criterion}</li>)}</ul></section>
      </div></article>
      <section className="card" aria-labelledby="attempt-heading"><div className="card-header"><h3 className="card-title" id="attempt-heading">Current or latest Attempt</h3></div><div className="card-body">
        {attempt ? <div className="vstack gap-2"><div><strong>Agent:</strong> {attempt.agentId}</div><div><strong>Status:</strong> {attempt.status}</div><code className="text-break">{attempt.id}</code><div className="small text-body-secondary">Authorized {formatted(attempt.authorizedAt)}</div>{attempt.abandonmentReason ? <div className="alert alert-warning mb-0">{attempt.abandonmentReason}</div> : null}</div> : <p className="mb-0">No Attempt has been projected.</p>}
      </div></section>
      <section className="card" aria-labelledby="checkpoint-heading"><div className="card-header"><h3 className="card-title" id="checkpoint-heading">Latest checkpoint</h3></div><div className="card-body">
        {checkpoint ? <div className="vstack gap-2"><div><strong>Kind:</strong> {checkpoint.checkpointKind}</div><div><strong>Evidence:</strong> {checkpoint.evidenceStatus}</div><div><strong>Branch:</strong> {checkpoint.targetBranch}</div><code className="text-break">{checkpoint.id}</code><code className="small text-break">{checkpoint.headCommitOid}</code></div> : <p className="mb-0">No Candidate checkpoint has been projected.</p>}
      </div></section>
    </div>
  );
}

export function DependencyDetail({ item }: { readonly item: CoordinationDependency }) {
  return (
    <article className={`card card-outline ${item.blocking ? "card-warning" : "card-success"}`}>
      <div className="card-body vstack gap-3">
        <div className="d-flex flex-wrap justify-content-between gap-2"><h3 className="h4 mb-0">{item.dependencyKind.replaceAll("_", " ")}</h3><span className={`badge ${item.blocking ? "text-bg-warning" : "text-bg-success"}`}>{item.blocking ? "blocking" : "satisfied"}</span></div>
        <code className="text-break">{item.id}</code>
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
