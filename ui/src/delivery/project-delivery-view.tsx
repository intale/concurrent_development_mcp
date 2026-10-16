import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { DataTable, Timestamp } from "../data-table.js";
import { ContextLink as Link } from "../navigation.js";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type {
  CandidateConnection,
  CandidateDetail,
  MergeConnection,
  MergeDetail,
  ObligationConnection,
  ReleaseConnection,
  ReleaseDetail,
  VerificationDetail
} from "./project-delivery-model.js";
import { badgeClass, humanized } from "./project-delivery-model.js";


export function PageHeading({ description, headingRef, title }: {
  readonly description: string;
  readonly headingRef: RefObject<HTMLHeadingElement>;
  readonly title: string;
}) {
  return <div><h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>{title}</h2><p className="text-body-secondary mb-0">{description}</p></div>;
}

export function useDeliveryHeading(title: string, identity: string): RefObject<HTMLHeadingElement> {
  const headingRef = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    document.title = `${title} · Coordinator`;
    headingRef.current?.focus();
  }, [title, identity]);
  return headingRef;
}

export function LoadingState({ label }: { readonly label: string }) {
  return <div aria-live="polite" className="card" role="status"><div className="card-body d-flex align-items-center gap-3"><span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" /><span>Loading {label.toLowerCase()}…</span></div></div>;
}

export function InitialError({ label, message, onRetry }: {
  readonly label: string;
  readonly message: string;
  readonly onRetry: () => void;
}) {
  return <div className="alert alert-danger" role="alert"><h3 className="h5">{label} could not be loaded</h3><p>{message}</p><RetryRefresh announcementLabel={label} buttonClassName="btn btn-outline-light" onRetry={onRetry}>Retry</RetryRefresh></div>;
}

export function AvailableStale({ message, onRetry }: { readonly message: string; readonly onRetry: () => void }) {
  return <div className="alert alert-warning" role="alert"><p>The last available content remains visible. {message}</p><RetryRefresh announcementLabel="Delivery view" buttonClassName="btn btn-outline-dark" onRetry={onRetry}>Retry refresh</RetryRefresh></div>;
}

export function PaginationControls({ canPrevious, nextCursor, onNext, onPrevious }: {
  readonly canPrevious: boolean;
  readonly nextCursor: string | null;
  readonly onNext: (cursor: string) => void;
  readonly onPrevious: () => void;
}) {
  if (!canPrevious && !nextCursor) return null;
  return <nav aria-label="Pagination" className="d-flex flex-wrap gap-2"><button className="btn btn-outline-secondary" disabled={!canPrevious} onClick={onPrevious} type="button">Previous page</button><button className="btn btn-outline-primary" disabled={!nextCursor} onClick={() => { if (nextCursor) onNext(nextCursor); }} type="button">Next page</button></nav>;
}

export function CandidateTable({ connection, hrefFor }: { readonly connection: CandidateConnection; readonly hrefFor: (id: string) => string }) {
  return <DataTable caption="Candidate checkpoints" rows={connection.nodes} rowKey={(row) => row.id} emptyMessage="No Candidate checkpoints match these filters." columns={[{ key: "id", label: "ID", render: (row) => <Link to={hrefFor(row.id)}><code>{row.id}</code></Link> }, { key: "kind", label: "Kind", render: (row) => <span className="badge text-bg-primary">{humanized(row.checkpointKind)}</span> }, { key: "workItem", label: "WorkItem", render: (row) => <code>{row.workItemId}</code> }, { key: "commit", label: "Head commit", render: (row) => <code>{row.headCommitOid}</code> }, { key: "submitted", label: "Submitted", render: (row) => <Timestamp value={row.submittedAt} /> }]}/>;
}

export function ObligationTable({ connection, hrefFor }: { readonly connection: ObligationConnection; readonly hrefFor: (id: string) => string }) {
  return <DataTable caption="Verification obligations" rows={connection.nodes} rowKey={(row) => row.id} emptyMessage="No verification obligations match these filters." columns={[{ key: "id", label: "ID", render: (row) => <Link to={hrefFor(row.id)}><code>{row.id}</code></Link> }, { key: "status", label: "Status", render: (row) => <span className={`badge ${badgeClass(row.status)}`}>{humanized(row.status)}</span> }, { key: "kind", label: "Kind", render: (row) => humanized(row.kind) }, { key: "candidates", label: "Source/target candidates", render: (row) => <><code>{row.sourceCandidateId}</code> → <code>{row.targetCandidateId}</code></> }, { key: "evidence", label: "Evidence/missing", render: (row) => `${row.evidenceCount} submitted · ${row.missingEvidenceKinds.length} missing` }]}/>;
}

export function MergeTable({ connection, hrefFor }: { readonly connection: MergeConnection; readonly hrefFor: (id: string) => string }) {
  return <DataTable caption="Merge snapshots" rows={connection.nodes} rowKey={(row) => row.id} emptyMessage="No merge snapshots are available." columns={[{ key: "id", label: "ID", render: (row) => <Link to={hrefFor(row.id)}><code>{row.id}</code></Link> }, { key: "branch", label: "Branch", render: (row) => row.targetBranch }, { key: "verification", label: "Verification status", render: (row) => <span className={`badge ${badgeClass(row.verificationStatus)}`}>{humanized(row.verificationStatus)}</span> }, { key: "commit", label: "Commit", render: (row) => <code>{row.mergeCommitOid}</code> }, { key: "candidates", label: "Candidate count", render: (row) => row.candidateCount }, { key: "produced", label: "Produced", render: (row) => <Timestamp value={row.producedAt} /> }]}/>;
}

export function ReleaseTable({ connection, hrefFor }: { readonly connection: ReleaseConnection; readonly hrefFor: (id: string) => string }) {
  return <DataTable caption="ReleaseSets" rows={connection.nodes} rowKey={(row) => row.id} emptyMessage="No ReleaseSets match these filters." columns={[{ key: "id", label: "ID", render: (row) => <Link to={hrefFor(row.id)}><code>{row.id}</code></Link> }, { key: "status", label: "Status", render: (row) => <span className={`badge ${badgeClass(row.status)}`}>{humanized(row.status)}</span> }, { key: "changeSet", label: "ChangeSet", render: (row) => <code>{row.changeSetId}</code> }, { key: "members", label: "Member count", render: (row) => row.memberCount }, { key: "verification", label: "Verification status", render: (row) => humanized(row.verificationStatus) }, { key: "prepared", label: "Prepared", render: (row) => <Timestamp value={row.preparedAt} /> }]}/>;
}

export function CandidateDetailCard({ detail }: { readonly detail: CandidateDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header"><h3 className="card-title mb-0">Candidate checkpoint</h3></div><div className="card-body vstack gap-3"><CopyIdentifier label="Candidate checkpoint ID" value={detail.checkpoint.id} /><dl className="row mb-0"><dt className="col-md-3">Coordination</dt><dd className="col-md-9 text-break"><code>{detail.checkpoint.changeSetId}</code> · <code>{detail.checkpoint.workItemId}</code> · <code>{detail.checkpoint.attemptId}</code></dd><dt className="col-md-3">Commit range</dt><dd className="col-md-9 text-break"><code>{detail.checkpoint.baseCommitOid}</code> → <code>{detail.checkpoint.headCommitOid}</code></dd><dt className="col-md-3">Evidence</dt><dd className="col-md-9">Manifest {detail.checkpoint.manifestObserved ? "observed" : "not observed"}; build context {detail.checkpoint.buildContextObserved ? "observed" : "not observed"}</dd><dt className="col-md-3">Impact surface</dt><dd className="col-md-9 text-break"><code>{detail.impactSurfaceDigest ?? "not observed"}</code></dd></dl></div></section><DataTable caption={`${humanized(detail.impactDirection)} potential impacts`} rows={detail.impactRelationships.nodes} rowKey={(row) => row.counterpart.id} emptyMessage="No potential impact relationships are available." columns={[{ key: "counterpart", label: "Counterpart", render: (row) => <code>{row.counterpart.id}</code> }, { key: "kind", label: "Relationship kind", render: (row) => humanized(row.relationshipKind) }, { key: "reasons", label: "Reasons", render: (row) => row.reasons.map((reason) => `${humanized(reason.kind)} · ${reason.matches.join(", ")}`).join("; ") }]}/></div>;
}

export function VerificationDetailCard({ detail }: { readonly detail: VerificationDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title mb-0">Verification obligation</h3><span className={`badge ${badgeClass(detail.obligation.status)}`}>{humanized(detail.obligation.status)}</span></div><div className="card-body vstack gap-3"><CopyIdentifier label="Verification obligation ID" value={detail.obligation.id} /><dl className="row mb-0"><dt className="col-md-3">Required evidence</dt><dd className="col-md-9">{detail.requiredEvidence.join(", ") || "None"}</dd><dt className="col-md-3">Missing evidence</dt><dd className="col-md-9">{detail.obligation.missingEvidenceKinds.join(", ") || "None"}</dd><dt className="col-md-3">Reasons</dt><dd className="col-md-9">{detail.reasons.map((reason) => `${humanized(reason.kind)}: ${reason.matches.join(", ")}`).join("; ") || "None"}</dd></dl></div></section><DataTable caption="Evidence" rows={detail.evidence.nodes} rowKey={(row) => row.id} emptyMessage="No evidence has been projected." columns={[{ key: "id", label: "ID", render: (row) => <code>{row.id}</code> }, { key: "kind", label: "Kind", render: (row) => humanized(row.evidenceKind) }, { key: "outcome", label: "Outcome", render: (row) => <span className={`badge ${badgeClass(row.conclusion)}`}>{humanized(row.conclusion)}</span> }, { key: "digest", label: "Digest", render: (row) => <code>{row.resultDigest}</code> }, { key: "produced", label: "Produced", render: (row) => <Timestamp value={row.producedAt} /> }]}/></div>;
}

export function MergeDetailCard({ detail }: { readonly detail: MergeDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title mb-0">Merge snapshot</h3><span className={`badge ${badgeClass(detail.snapshot.verificationStatus)}`}>{humanized(detail.snapshot.verificationStatus)}</span></div><div className="card-body vstack gap-3"><CopyIdentifier label="Merge snapshot ID" value={detail.snapshot.id} /><dl className="row mb-0"><dt className="col-md-3">Target branch</dt><dd className="col-md-9">{detail.snapshot.targetBranch}</dd><dt className="col-md-3">Commit range</dt><dd className="col-md-9 text-break"><code>{detail.snapshot.targetBaseCommitOid}</code> → <code>{detail.snapshot.mergeCommitOid}</code></dd><dt className="col-md-3">Ordered Candidates</dt><dd className="col-md-9"><ol className="mb-0">{detail.candidates.map((candidate) => <li className="text-break" key={candidate.id}><code>{candidate.id}</code> · {candidate.workItemId} · {candidate.attemptId}</li>)}</ol></dd></dl></div></section><DataTable caption="Authorization decisions" rows={detail.authorizations.nodes} rowKey={(row) => row.id} emptyMessage="No authorization decisions are available." columns={[{ key: "id", label: "ID", render: (row) => <code>{row.id}</code> }, { key: "outcome", label: "Outcome", render: (row) => <span className={`badge ${badgeClass(row.outcome)}`}>{humanized(row.outcome)}</span> }, { key: "policy", label: "Policy", render: (row) => row.policyVersion }, { key: "reasons", label: "Reasons count", render: (row) => row.reasonCount }, { key: "decided", label: "Decided", render: (row) => <Timestamp value={row.decidedAt} /> }]}/></div>;
}

export function ReleaseDetailCard({ detail }: { readonly detail: ReleaseDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title mb-0">ReleaseSet</h3><span className={`badge ${badgeClass(detail.releaseSet.status)}`}>{humanized(detail.releaseSet.status)}</span></div><div className="card-body vstack gap-3"><CopyIdentifier label="ReleaseSet ID" value={detail.releaseSet.id} /><dl className="row mb-0"><dt className="col-md-3">Verification attempts</dt><dd className="col-md-9">{detail.verificationAttemptCount}</dd><dt className="col-md-3">Activated</dt><dd className="col-md-9">{detail.activated ? "Yes" : "No"}</dd><dt className="col-md-3">Compensation requested</dt><dd className="col-md-9">{detail.compensationRequested ? "Yes" : "No"}</dd><dt className="col-md-3">Completion outcome</dt><dd className="col-md-9">{detail.completionOutcome ? humanized(detail.completionOutcome) : "Not completed"}</dd></dl></div></section><DataTable caption="ReleaseSet members" rows={detail.members} rowKey={(row) => `${row.position}:${row.repositoryId}`} emptyMessage="No ReleaseSet members are available." columns={[{ key: "position", label: "Position", render: (row) => row.position }, { key: "repository", label: "Repository", render: (row) => <code>{row.repositoryId}</code> }, { key: "snapshot", label: "Merge snapshot", render: (row) => <code>{row.mergeSnapshotId}</code> }, { key: "candidates", label: "Candidates", render: (row) => row.orderedCandidateIds.map((id) => <div key={id}><code>{id}</code></div>) }]}/><DataTable caption="Integration attempts" rows={detail.integrations} rowKey={(row) => `${row.repositoryId}:${row.attemptNumber}`} emptyMessage="No integration attempts are available." columns={[{ key: "repository", label: "Repository", render: (row) => <code>{row.repositoryId}</code> }, { key: "attempt", label: "Attempt number/ID", render: (row) => <>{row.attemptNumber} · <code>{row.attemptId}</code></> }, { key: "outcome", label: "Outcome", render: (row) => <span className={`badge ${badgeClass(row.outcome)}`}>{humanized(row.outcome)}</span> }, { key: "failure", label: "Failure", render: (row) => row.failureCode ?? "—" }]}/></div>;
}
