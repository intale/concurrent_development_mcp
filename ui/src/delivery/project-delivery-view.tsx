import { useEffect, useRef } from "react";
import type { RefObject, ReactNode } from "react";
import { Link, NavLink } from "react-router-dom";
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
import { badgeClass, formatted, humanized } from "./project-delivery-model.js";

export function DeliveryNavigation({ basePath }: { readonly basePath: string }) {
  const items = [
    ["Candidates", `${basePath}/candidates`],
    ["Obligations", `${basePath}/obligations`],
    ["Merge snapshots", `${basePath}/merge-snapshots`],
    ["ReleaseSets", `${basePath}/release-sets`]
  ] as const;
  return (
    <nav aria-label="Delivery views" className="overflow-x-auto">
      <ul className="nav nav-pills flex-nowrap gap-2">
        {items.map(([label, to]) => <li className="nav-item" key={to}><NavLink className="nav-link text-nowrap" to={to}>{label}</NavLink></li>)}
      </ul>
    </nav>
  );
}

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

function CollectionCard({ children, count, empty, title }: {
  readonly children: ReactNode;
  readonly count: number;
  readonly empty: string;
  readonly title: string;
}) {
  return (
    <section aria-label={title} className="card">
      <div className="card-header d-flex flex-wrap align-items-center justify-content-between gap-2"><h3 className="card-title mb-0">{title}</h3><span className="badge text-bg-secondary">{count} on this page</span></div>
      <div className="card-body">{count === 0 ? <p className="text-body-secondary mb-0">{empty}</p> : <div className="row g-3">{children}</div>}</div>
    </section>
  );
}

export function CandidateCards({ connection, hrefFor }: { readonly connection: CandidateConnection; readonly hrefFor: (id: string) => string }) {
  return <CollectionCard count={connection.nodes.length} empty="No Candidate checkpoints match these filters." title="Candidate checkpoints">{connection.nodes.map((candidate) => <div className="col-12 col-xl-6" key={candidate.id}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><h4 className="h6 text-break"><Link to={hrefFor(candidate.id)}><code>{candidate.id}</code></Link></h4><span className="badge text-bg-primary">{humanized(candidate.checkpointKind)}</span></div><dl className="row small mb-0"><dt className="col-sm-4">ChangeSet</dt><dd className="col-sm-8 text-break"><code>{candidate.changeSetId}</code></dd><dt className="col-sm-4">WorkItem</dt><dd className="col-sm-8 text-break"><code>{candidate.workItemId}</code></dd><dt className="col-sm-4">Head commit</dt><dd className="col-sm-8 text-break"><code>{candidate.headCommitOid}</code></dd><dt className="col-sm-4">Submitted</dt><dd className="col-sm-8">{formatted(candidate.submittedAt)}</dd></dl></div></article></div>)}</CollectionCard>;
}

export function ObligationCards({ connection, hrefFor }: { readonly connection: ObligationConnection; readonly hrefFor: (id: string) => string }) {
  return <CollectionCard count={connection.nodes.length} empty="No verification obligations match these filters." title="Verification obligations">{connection.nodes.map((obligation) => <div className="col-12 col-xl-6" key={obligation.id}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><h4 className="h6 text-break"><Link to={hrefFor(obligation.id)}><code>{obligation.id}</code></Link></h4><span className={`badge ${badgeClass(obligation.status)}`}>{humanized(obligation.status)}</span></div><dl className="row small mb-0"><dt className="col-sm-4">Kind</dt><dd className="col-sm-8">{humanized(obligation.kind)}</dd><dt className="col-sm-4">Candidates</dt><dd className="col-sm-8 text-break"><code>{obligation.sourceCandidateId}</code> → <code>{obligation.targetCandidateId}</code></dd><dt className="col-sm-4">Evidence</dt><dd className="col-sm-8">{obligation.evidenceCount} submitted · {obligation.missingEvidenceKinds.length} missing</dd></dl></div></article></div>)}</CollectionCard>;
}

export function MergeCards({ connection, hrefFor }: { readonly connection: MergeConnection; readonly hrefFor: (id: string) => string }) {
  return <CollectionCard count={connection.nodes.length} empty="No merge snapshots are available." title="Merge snapshots">{connection.nodes.map((snapshot) => <div className="col-12 col-xl-6" key={snapshot.id}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><h4 className="h6 text-break"><Link to={hrefFor(snapshot.id)}><code>{snapshot.id}</code></Link></h4><span className={`badge ${badgeClass(snapshot.verificationStatus)}`}>{humanized(snapshot.verificationStatus)}</span></div><dl className="row small mb-0"><dt className="col-sm-4">Branch</dt><dd className="col-sm-8">{snapshot.targetBranch}</dd><dt className="col-sm-4">Merge commit</dt><dd className="col-sm-8 text-break"><code>{snapshot.mergeCommitOid}</code></dd><dt className="col-sm-4">Candidates</dt><dd className="col-sm-8">{snapshot.candidateCount}</dd><dt className="col-sm-4">Produced</dt><dd className="col-sm-8">{formatted(snapshot.producedAt)}</dd></dl></div></article></div>)}</CollectionCard>;
}

export function ReleaseCards({ connection, hrefFor }: { readonly connection: ReleaseConnection; readonly hrefFor: (id: string) => string }) {
  return <CollectionCard count={connection.nodes.length} empty="No ReleaseSets match these filters." title="ReleaseSets">{connection.nodes.map((release) => <div className="col-12 col-xl-6" key={release.id}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><h4 className="h6 text-break"><Link to={hrefFor(release.id)}><code>{release.id}</code></Link></h4><span className={`badge ${badgeClass(release.status)}`}>{humanized(release.status)}</span></div><dl className="row small mb-0"><dt className="col-sm-4">ChangeSet</dt><dd className="col-sm-8 text-break"><code>{release.changeSetId}</code></dd><dt className="col-sm-4">Members</dt><dd className="col-sm-8">{release.memberCount}</dd><dt className="col-sm-4">Verification</dt><dd className="col-sm-8">{humanized(release.verificationStatus)}</dd><dt className="col-sm-4">Prepared</dt><dd className="col-sm-8">{formatted(release.preparedAt)}</dd></dl></div></article></div>)}</CollectionCard>;
}

export function CandidateDetailCard({ detail }: { readonly detail: CandidateDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header"><h3 className="card-title mb-0">Candidate checkpoint</h3></div><div className="card-body vstack gap-3"><CopyIdentifier label="Candidate checkpoint ID" value={detail.checkpoint.id} /><dl className="row mb-0"><dt className="col-md-3">Coordination</dt><dd className="col-md-9 text-break"><code>{detail.checkpoint.changeSetId}</code> · <code>{detail.checkpoint.workItemId}</code> · <code>{detail.checkpoint.attemptId}</code></dd><dt className="col-md-3">Commit range</dt><dd className="col-md-9 text-break"><code>{detail.checkpoint.baseCommitOid}</code> → <code>{detail.checkpoint.headCommitOid}</code></dd><dt className="col-md-3">Evidence</dt><dd className="col-md-9">Manifest {detail.checkpoint.manifestObserved ? "observed" : "not observed"}; build context {detail.checkpoint.buildContextObserved ? "observed" : "not observed"}</dd><dt className="col-md-3">Impact surface</dt><dd className="col-md-9 text-break"><code>{detail.impactSurfaceDigest ?? "not observed"}</code></dd></dl></div></section><CollectionCard count={detail.impactRelationships.nodes.length} empty="No potential impact relationships are available." title={`${humanized(detail.impactDirection)} potential impacts`}>{detail.impactRelationships.nodes.map((relationship) => <div className="col-12 col-xl-6" key={relationship.counterpart.id}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><code className="text-break">{relationship.counterpart.id}</code><span className="badge text-bg-secondary">{humanized(relationship.relationshipKind)}</span></div>{relationship.reasons.map((reason) => <p className="small mb-1 mt-2" key={`${relationship.counterpart.id}:${reason.kind}`}>{humanized(reason.kind)} · {reason.matches.join(", ")}</p>)}</div></article></div>)}</CollectionCard></div>;
}

export function VerificationDetailCard({ detail }: { readonly detail: VerificationDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title mb-0">Verification obligation</h3><span className={`badge ${badgeClass(detail.obligation.status)}`}>{humanized(detail.obligation.status)}</span></div><div className="card-body vstack gap-3"><CopyIdentifier label="Verification obligation ID" value={detail.obligation.id} /><dl className="row mb-0"><dt className="col-md-3">Required evidence</dt><dd className="col-md-9">{detail.requiredEvidence.join(", ") || "None"}</dd><dt className="col-md-3">Missing evidence</dt><dd className="col-md-9">{detail.obligation.missingEvidenceKinds.join(", ") || "None"}</dd><dt className="col-md-3">Reasons</dt><dd className="col-md-9">{detail.reasons.map((reason) => `${humanized(reason.kind)}: ${reason.matches.join(", ")}`).join("; ") || "None"}</dd></dl></div></section><CollectionCard count={detail.evidence.nodes.length} empty="No evidence has been projected." title="Evidence">{detail.evidence.nodes.map((evidence) => <div className="col-12 col-xl-6" key={evidence.id}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><code className="text-break">{evidence.id}</code><span className={`badge ${badgeClass(evidence.conclusion)}`}>{humanized(evidence.conclusion)}</span></div><dl className="row small mt-2 mb-0"><dt className="col-sm-4">Kind</dt><dd className="col-sm-8">{humanized(evidence.evidenceKind)}</dd><dt className="col-sm-4">Result digest</dt><dd className="col-sm-8 text-break"><code>{evidence.resultDigest}</code></dd><dt className="col-sm-4">Produced</dt><dd className="col-sm-8">{formatted(evidence.producedAt)}</dd></dl></div></article></div>)}</CollectionCard></div>;
}

export function MergeDetailCard({ detail }: { readonly detail: MergeDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title mb-0">Merge snapshot</h3><span className={`badge ${badgeClass(detail.snapshot.verificationStatus)}`}>{humanized(detail.snapshot.verificationStatus)}</span></div><div className="card-body vstack gap-3"><CopyIdentifier label="Merge snapshot ID" value={detail.snapshot.id} /><dl className="row mb-0"><dt className="col-md-3">Target branch</dt><dd className="col-md-9">{detail.snapshot.targetBranch}</dd><dt className="col-md-3">Commit range</dt><dd className="col-md-9 text-break"><code>{detail.snapshot.targetBaseCommitOid}</code> → <code>{detail.snapshot.mergeCommitOid}</code></dd><dt className="col-md-3">Ordered Candidates</dt><dd className="col-md-9"><ol className="mb-0">{detail.candidates.map((candidate) => <li className="text-break" key={candidate.id}><code>{candidate.id}</code> · {candidate.workItemId} · {candidate.attemptId}</li>)}</ol></dd></dl></div></section><CollectionCard count={detail.authorizations.nodes.length} empty="No authorization decisions are available." title="Authorization decisions">{detail.authorizations.nodes.map((decision) => <div className="col-12 col-xl-6" key={decision.id}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><code className="text-break">{decision.id}</code><span className={`badge ${badgeClass(decision.outcome)}`}>{humanized(decision.outcome)}</span></div><dl className="row small mt-2 mb-0"><dt className="col-sm-4">Policy</dt><dd className="col-sm-8">{decision.policyVersion}</dd><dt className="col-sm-4">Reasons</dt><dd className="col-sm-8">{decision.reasonCount}</dd><dt className="col-sm-4">Decided</dt><dd className="col-sm-8">{formatted(decision.decidedAt)}</dd></dl></div></article></div>)}</CollectionCard></div>;
}

export function ReleaseDetailCard({ detail }: { readonly detail: ReleaseDetail }) {
  return <div className="vstack gap-3"><section className="card"><div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title mb-0">ReleaseSet</h3><span className={`badge ${badgeClass(detail.releaseSet.status)}`}>{humanized(detail.releaseSet.status)}</span></div><div className="card-body vstack gap-3"><CopyIdentifier label="ReleaseSet ID" value={detail.releaseSet.id} /><dl className="row mb-0"><dt className="col-md-3">Verification attempts</dt><dd className="col-md-9">{detail.verificationAttemptCount}</dd><dt className="col-md-3">Activated</dt><dd className="col-md-9">{detail.activated ? "Yes" : "No"}</dd><dt className="col-md-3">Compensation requested</dt><dd className="col-md-9">{detail.compensationRequested ? "Yes" : "No"}</dd><dt className="col-md-3">Completion outcome</dt><dd className="col-md-9">{detail.completionOutcome ? humanized(detail.completionOutcome) : "Not completed"}</dd></dl></div></section><CollectionCard count={detail.members.length} empty="No ReleaseSet members are available." title="ReleaseSet members">{detail.members.map((member) => <div className="col-12 col-xl-6" key={`${member.position}:${member.repositoryId}`}><article className="card h-100 border"><div className="card-body"><h4 className="h6 text-break">#{member.position} · <code>{member.repositoryId}</code></h4><CopyIdentifier label="Merge snapshot ID" value={member.mergeSnapshotId} /><p className="small mb-1 mt-3">Candidates</p><ul className="mb-0 ps-3">{member.orderedCandidateIds.map((candidateId) => <li className="text-break" key={candidateId}><code>{candidateId}</code></li>)}</ul></div></article></div>)}</CollectionCard><CollectionCard count={detail.integrations.length} empty="No integration attempts are available." title="Integration attempts">{detail.integrations.map((integration) => <div className="col-12 col-xl-6" key={`${integration.repositoryId}:${integration.attemptNumber}`}><article className="card h-100 border"><div className="card-body"><div className="d-flex flex-wrap justify-content-between gap-2"><code className="text-break">{integration.repositoryId}</code><span className={`badge ${badgeClass(integration.outcome)}`}>{humanized(integration.outcome)}</span></div><p className="small mb-0 mt-2">Attempt {integration.attemptNumber} · <code>{integration.attemptId}</code>{integration.failureCode ? ` · ${integration.failureCode}` : ""}</p></div></article></div>)}</CollectionCard></div>;
}
