import { Link } from "react-router-dom";
import type {
  BatchDetail,
  BatchPage,
  CandidateDetail,
  MergeDetail,
  ProjectDelivery,
  ReleaseDetail,
  VerificationDetail
} from "./project-delivery-model.js";
import { badgeClass, formatted, humanized } from "./project-delivery-model.js";

export interface ProjectDeliveryViewProps {
  readonly batch: BatchDetail | null;
  readonly batches: BatchPage | null;
  readonly browser: ProjectDelivery | null;
  readonly candidate: CandidateDetail | null;
  readonly errorMessage: string | null;
  readonly hrefForBatch: (id: string) => string;
  readonly hrefForCandidate: (id: string) => string;
  readonly hrefForMerge: (id: string) => string;
  readonly hrefForObligation: (id: string) => string;
  readonly hrefForRelease: (id: string) => string;
  readonly loading: boolean;
  readonly merge: MergeDetail | null;
  readonly onNextAuthorizations: (cursor: string) => void;
  readonly onNextBatchItems: (cursor: string) => void;
  readonly onNextBatches: (cursor: string) => void;
  readonly onNextCandidates: (cursor: string) => void;
  readonly onNextEvidence: (cursor: string) => void;
  readonly onNextImpacts: (cursor: string) => void;
  readonly onNextMerges: (cursor: string) => void;
  readonly onNextObligations: (cursor: string) => void;
  readonly onNextReleases: (cursor: string) => void;
  readonly onRetry: () => void;
  readonly refreshing: boolean;
  readonly release: ReleaseDetail | null;
  readonly verification: VerificationDetail | null;
}

function NextButton({ cursor, label, onNext }: {
  readonly cursor: string | null | undefined;
  readonly label: string;
  readonly onNext: (cursor: string) => void;
}) {
  return cursor ? <button className="btn btn-outline-primary" onClick={() => onNext(cursor)} type="button">{label}</button> : null;
}

function CandidateDetailCard({ detail, onNext }: {
  readonly detail: CandidateDetail;
  readonly onNext: (cursor: string) => void;
}) {
  return (
    <section aria-labelledby="candidate-detail-heading" className="card card-outline card-primary">
      <div className="card-header"><h2 className="card-title" id="candidate-detail-heading">Candidate checkpoint · {detail.checkpoint.id}</h2></div>
      <div className="card-body vstack gap-3">
        <dl className="row mb-0">
          <dt className="col-sm-3">Coordination</dt><dd className="col-sm-9"><code>{detail.checkpoint.changeSetId}</code> · <code>{detail.checkpoint.workItemId}</code> · <code>{detail.checkpoint.attemptId}</code></dd>
          <dt className="col-sm-3">Commit</dt><dd className="col-sm-9"><code>{detail.checkpoint.baseCommitOid}</code> → <code>{detail.checkpoint.headCommitOid}</code></dd>
          <dt className="col-sm-3">Evidence</dt><dd className="col-sm-9">manifest {detail.checkpoint.manifestObserved ? "observed" : "not yet observed"}; build context {detail.checkpoint.buildContextObserved ? "observed" : "not yet observed"}</dd>
          <dt className="col-sm-3">Impact surface</dt><dd className="col-sm-9"><code>{detail.impactSurfaceDigest ?? "not yet observed"}</code></dd>
        </dl>
        <h3 className="h6 mb-0">{humanized(detail.impactDirection)} potential impacts</h3>
        <div className="list-group">
          {detail.impactRelationships.nodes.length === 0 ? <span className="list-group-item text-body-secondary">No potential relationships are available.</span> : detail.impactRelationships.nodes.map((relationship) => (
            <div className="list-group-item" key={relationship.counterpart.id}>
              <div className="d-flex justify-content-between gap-3"><code>{relationship.counterpart.id}</code><span className="badge text-bg-secondary">{humanized(relationship.relationshipKind)}</span></div>
              {relationship.reasons.map((reason) => <div className="small mt-1" key={`${relationship.counterpart.id}:${reason.kind}`}>{humanized(reason.kind)} · {reason.matches.join(", ")}</div>)}
            </div>
          ))}
        </div>
      </div>
      {detail.impactRelationships.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={detail.impactRelationships.pageInfo.endCursor} label="Next impact page" onNext={onNext} /></div> : null}
    </section>
  );
}

function VerificationDetailCard({ detail, onNext }: {
  readonly detail: VerificationDetail;
  readonly onNext: (cursor: string) => void;
}) {
  return (
    <section aria-labelledby="verification-detail-heading" className="card card-outline card-warning">
      <div className="card-header d-flex justify-content-between"><h2 className="card-title" id="verification-detail-heading">Verification · {detail.obligation.id}</h2><span className={`badge ${badgeClass(detail.obligation.status)}`}>{humanized(detail.obligation.status)}</span></div>
      <div className="card-body vstack gap-3">
        <p className="mb-0"><strong>Required:</strong> {detail.requiredEvidence.join(", ")} · <strong>Missing:</strong> {detail.obligation.missingEvidenceKinds.join(", ") || "none"}</p>
        <div>{detail.reasons.map((reason) => <span className="badge text-bg-secondary me-2" key={reason.kind}>{humanized(reason.kind)} · {reason.matches.join(", ")}</span>)}</div>
        <div className="table-responsive"><table aria-label="Verification evidence" className="table table-sm table-hover align-middle mb-0"><thead><tr><th>Evidence</th><th>Kind</th><th>Conclusion</th><th>Produced</th></tr></thead><tbody>
          {detail.evidence.nodes.length === 0 ? <tr><td className="text-center" colSpan={4}>No evidence has been projected.</td></tr> : detail.evidence.nodes.map((evidence) => <tr key={evidence.id}><td><code>{evidence.id}</code><div className="small text-body-secondary">{evidence.resultDigest}</div></td><td>{humanized(evidence.evidenceKind)}</td><td><span className={`badge ${badgeClass(evidence.conclusion)}`}>{humanized(evidence.conclusion)}</span></td><td>{formatted(evidence.producedAt)}</td></tr>)}
        </tbody></table></div>
      </div>
      {detail.evidence.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={detail.evidence.pageInfo.endCursor} label="Next evidence page" onNext={onNext} /></div> : null}
    </section>
  );
}

function MergeDetailCard({ detail, onNext }: {
  readonly detail: MergeDetail;
  readonly onNext: (cursor: string) => void;
}) {
  return (
    <section aria-labelledby="merge-detail-heading" className="card card-outline card-info">
      <div className="card-header"><h2 className="card-title" id="merge-detail-heading">Merge snapshot · {detail.snapshot.id}</h2></div>
      <div className="card-body vstack gap-3">
        <p className="mb-0"><code>{detail.snapshot.targetBaseCommitOid}</code> → <code>{detail.snapshot.mergeCommitOid}</code> · <span className={`badge ${badgeClass(detail.snapshot.verificationStatus)}`}>{humanized(detail.snapshot.verificationStatus)}</span></p>
        <div><h3 className="h6">Ordered Candidates</h3><ol>{detail.candidates.map((candidate) => <li key={candidate.id}><code>{candidate.id}</code> · {candidate.workItemId} · {candidate.attemptId}</li>)}</ol></div>
        <div className="table-responsive"><table aria-label="Merge authorizations" className="table table-sm table-hover align-middle mb-0"><thead><tr><th>Decision</th><th>Outcome</th><th>Reasons</th><th>Decided</th></tr></thead><tbody>
          {detail.authorizations.nodes.length === 0 ? <tr><td className="text-center" colSpan={4}>No authorization decisions are available.</td></tr> : detail.authorizations.nodes.map((decision) => <tr key={decision.id}><td><code>{decision.id}</code><div className="small">{decision.decisionDigest}</div></td><td><span className={`badge ${badgeClass(decision.outcome)}`}>{humanized(decision.outcome)}</span></td><td>{decision.reasonCount}</td><td>{formatted(decision.decidedAt)}</td></tr>)}
        </tbody></table></div>
      </div>
      {detail.authorizations.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={detail.authorizations.pageInfo.endCursor} label="Next authorization page" onNext={onNext} /></div> : null}
    </section>
  );
}

function ReleaseDetailCard({ detail }: { readonly detail: ReleaseDetail }) {
  return (
    <section aria-labelledby="release-detail-heading" className="card card-outline card-success">
      <div className="card-header"><h2 className="card-title" id="release-detail-heading">ReleaseSet · {detail.releaseSet.id}</h2></div>
      <div className="card-body vstack gap-3">
        <p className="mb-0"><span className={`badge ${badgeClass(detail.releaseSet.status)}`}>{humanized(detail.releaseSet.status)}</span> · {detail.verificationAttemptCount} verification attempts · activated {detail.activated ? "yes" : "no"} · compensation requested {detail.compensationRequested ? "yes" : "no"}</p>
        <div className="table-responsive"><table aria-label="ReleaseSet members" className="table table-sm table-hover align-middle mb-0"><thead><tr><th>Position</th><th>Repository</th><th>Merge snapshot</th><th>Candidates</th></tr></thead><tbody>{detail.members.map((member) => <tr key={member.repositoryId}><td>{member.position}</td><td><code>{member.repositoryId}</code></td><td><code>{member.mergeSnapshotId}</code></td><td>{member.candidateCount}</td></tr>)}</tbody></table></div>
        {detail.integrations.length > 0 ? <div><h3 className="h6">Integration attempts</h3><ul>{detail.integrations.map((integration) => <li key={`${integration.repositoryId}:${integration.attemptNumber}`}><code>{integration.repositoryId}</code> · {integration.attemptId} · {humanized(integration.outcome)}{integration.failureCode ? ` · ${integration.failureCode}` : ""}</li>)}</ul></div> : null}
      </div>
    </section>
  );
}

function BatchDetailCard({ detail, onNext }: {
  readonly detail: BatchDetail;
  readonly onNext: (cursor: string) => void;
}) {
  return (
    <section aria-labelledby="batch-detail-heading" className="card card-outline card-dark">
      <div className="card-header"><h2 className="card-title" id="batch-detail-heading">Global operation batch · {detail.batch.id}</h2></div>
      <div className="card-body p-0"><div className="table-responsive"><table aria-label="Operation batch items" className="table table-sm table-hover align-middle mb-0"><thead><tr><th>Index</th><th>Command</th><th>Status</th><th>Outcome</th></tr></thead><tbody>
        {detail.items.nodes.map((item) => <tr key={item.index}><td>{item.index}</td><td><code>{item.commandId}</code><div className="small">{humanized(item.targetTool)}</div></td><td><span className={`badge ${badgeClass(item.status)}`}>{humanized(item.status)}</span></td><td>{item.outcomeSummary ?? "Not finished"}{item.outcomeCode ? <div className="small text-danger">{item.outcomeCode}</div> : null}</td></tr>)}
      </tbody></table></div></div>
      {detail.items.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={detail.items.pageInfo.endCursor} label="Next batch items page" onNext={onNext} /></div> : null}
    </section>
  );
}

export function ProjectDeliveryView(props: ProjectDeliveryViewProps) {
  if (props.loading && !props.browser) return <div className="card"><div className="card-body d-flex align-items-center gap-3" role="status"><span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" /><span>Loading project delivery…</span></div></div>;
  if (props.errorMessage && !props.browser) return <div className="alert alert-danger" role="alert"><h2 className="h5">Project delivery could not be loaded</h2><p>{props.errorMessage}</p><button className="btn btn-outline-light btn-sm" onClick={props.onRetry} type="button">Retry</button></div>;
  if (!props.browser) return <div className="alert alert-warning" role="status">This project is not available in the latest projection.</div>;

  const { candidates, mergeSnapshots, obligations, project, releaseSets } = props.browser;
  return (
    <div className="vstack gap-4">
      {props.errorMessage ? <div className="alert alert-warning" role="alert">The last available delivery view remains visible. {props.errorMessage}<button className="btn btn-outline-dark btn-sm ms-3" onClick={props.onRetry} type="button">Retry refresh</button></div> : null}
      {props.refreshing ? <div className="alert alert-info mb-0" role="status">Refreshing latest available delivery facts…</div> : null}
      <div aria-label="Delivery summary" className="row g-3">
        <div className="col-6 col-xl-3"><div className="small-box text-bg-primary"><div className="inner"><h2>{candidates.nodes.length}</h2><p>Candidate checkpoints</p></div><span className="small-box-icon"><i className="bi bi-check2-square" /></span></div></div>
        <div className="col-6 col-xl-3"><div className="small-box text-bg-warning"><div className="inner"><h2>{obligations.nodes.length}</h2><p>Verification obligations</p></div><span className="small-box-icon"><i className="bi bi-shield-check" /></span></div></div>
        <div className="col-6 col-xl-3"><div className="small-box text-bg-info"><div className="inner"><h2>{mergeSnapshots.nodes.length}</h2><p>Merge snapshots</p></div><span className="small-box-icon"><i className="bi bi-git" /></span></div></div>
        <div className="col-6 col-xl-3"><div className="small-box text-bg-success"><div className="inner"><h2>{releaseSets.nodes.length}</h2><p>ReleaseSets</p></div><span className="small-box-icon"><i className="bi bi-box-seam" /></span></div></div>
      </div>

      <section aria-labelledby="candidate-heading" className="card card-outline card-primary"><div className="card-header"><h2 className="card-title" id="candidate-heading">Candidate checkpoints</h2></div><div className="card-body p-0"><div className="table-responsive"><table aria-label="Candidate checkpoints" className="table table-hover align-middle mb-0"><thead><tr><th>Candidate</th><th>Coordination</th><th>Kind</th><th>Submitted</th></tr></thead><tbody>{candidates.nodes.length === 0 ? <tr><td className="text-center" colSpan={4}>No Candidate checkpoints match these filters.</td></tr> : candidates.nodes.map((candidate) => <tr key={candidate.id}><td><Link to={props.hrefForCandidate(candidate.id)}><code>{candidate.id}</code></Link><div className="small">{candidate.headCommitOid}</div></td><td><code>{candidate.changeSetId}</code><div className="small">{candidate.workItemId} · {candidate.attemptId}</div></td><td><span className="badge text-bg-primary">{humanized(candidate.checkpointKind)}</span></td><td>{formatted(candidate.submittedAt)}</td></tr>)}</tbody></table></div></div>{candidates.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={candidates.pageInfo.endCursor} label="Next Candidate page" onNext={props.onNextCandidates} /></div> : null}</section>
      {props.candidate ? <CandidateDetailCard detail={props.candidate} onNext={props.onNextImpacts} /> : null}

      <section aria-labelledby="obligation-heading" className="card card-outline card-warning"><div className="card-header"><h2 className="card-title" id="obligation-heading">Verification obligations</h2></div><div className="card-body p-0"><div className="table-responsive"><table aria-label="Verification obligations" className="table table-hover align-middle mb-0"><thead><tr><th>Obligation</th><th>Status</th><th>Candidates</th><th>Evidence</th></tr></thead><tbody>{obligations.nodes.length === 0 ? <tr><td className="text-center" colSpan={4}>No obligations match these filters.</td></tr> : obligations.nodes.map((obligation) => <tr key={obligation.id}><td><Link to={props.hrefForObligation(obligation.id)}><code>{obligation.id}</code></Link><div className="small">{humanized(obligation.enforcement)}</div></td><td><span className={`badge ${badgeClass(obligation.status)}`}>{humanized(obligation.status)}</span></td><td><code>{obligation.sourceCandidateId}</code> → <code>{obligation.targetCandidateId}</code></td><td>{obligation.evidenceCount} · {obligation.missingEvidenceKinds.length} missing</td></tr>)}</tbody></table></div></div>{obligations.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={obligations.pageInfo.endCursor} label="Next obligation page" onNext={props.onNextObligations} /></div> : null}</section>
      {props.verification ? <VerificationDetailCard detail={props.verification} onNext={props.onNextEvidence} /> : null}

      <section aria-labelledby="merge-heading" className="card card-outline card-info"><div className="card-header"><h2 className="card-title" id="merge-heading">Merge snapshots</h2></div><div className="card-body p-0"><div className="table-responsive"><table aria-label="Merge snapshots" className="table table-hover align-middle mb-0"><thead><tr><th>Snapshot</th><th>Branch</th><th>Candidates</th><th>Verification</th></tr></thead><tbody>{mergeSnapshots.nodes.length === 0 ? <tr><td className="text-center" colSpan={4}>No merge snapshots are available.</td></tr> : mergeSnapshots.nodes.map((snapshot) => <tr key={snapshot.id}><td><Link to={props.hrefForMerge(snapshot.id)}><code>{snapshot.id}</code></Link><div className="small">{snapshot.mergeCommitOid}</div></td><td>{snapshot.targetBranch}</td><td>{snapshot.candidateCount}</td><td><span className={`badge ${badgeClass(snapshot.verificationStatus)}`}>{humanized(snapshot.verificationStatus)}</span></td></tr>)}</tbody></table></div></div>{mergeSnapshots.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={mergeSnapshots.pageInfo.endCursor} label="Next merge page" onNext={props.onNextMerges} /></div> : null}</section>
      {props.merge ? <MergeDetailCard detail={props.merge} onNext={props.onNextAuthorizations} /> : null}

      <section aria-labelledby="release-heading" className="card card-outline card-success"><div className="card-header"><h2 className="card-title" id="release-heading">ReleaseSets</h2></div><div className="card-body p-0"><div className="table-responsive"><table aria-label="ReleaseSets" className="table table-hover align-middle mb-0"><thead><tr><th>ReleaseSet</th><th>ChangeSet</th><th>Members</th><th>Status</th></tr></thead><tbody>{releaseSets.nodes.length === 0 ? <tr><td className="text-center" colSpan={4}>No ReleaseSets match these filters.</td></tr> : releaseSets.nodes.map((release) => <tr key={release.id}><td><Link to={props.hrefForRelease(release.id)}><code>{release.id}</code></Link><div className="small">{formatted(release.preparedAt)}</div></td><td><code>{release.changeSetId}</code></td><td>{release.memberCount}</td><td><span className={`badge ${badgeClass(release.status)}`}>{humanized(release.status)}</span></td></tr>)}</tbody></table></div></div>{releaseSets.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={releaseSets.pageInfo.endCursor} label="Next ReleaseSet page" onNext={props.onNextReleases} /></div> : null}</section>
      {props.release ? <ReleaseDetailCard detail={props.release} /> : null}

      <section aria-labelledby="batches-heading" className="card card-outline card-dark"><div className="card-header"><h2 className="card-title" id="batches-heading">Global operation batches</h2></div><div className="card-body"><div className="alert alert-secondary"><strong>Global view.</strong> Batch commands are never attributed to a project from arbitrary input.</div><div className="table-responsive"><table aria-label="Global operation batches" className="table table-hover align-middle mb-0"><thead><tr><th>Batch</th><th>Tool</th><th>Status</th><th>Progress</th></tr></thead><tbody>{!props.batches || props.batches.nodes.length === 0 ? <tr><td className="text-center" colSpan={4}>No global batches match these filters.</td></tr> : props.batches.nodes.map((batch) => <tr key={batch.id}><td><Link to={props.hrefForBatch(batch.id)}><code>{batch.id}</code></Link><div className="small">{formatted(batch.createdAt)}</div></td><td>{humanized(batch.targetTool)}</td><td><span className={`badge ${badgeClass(batch.status)}`}>{humanized(batch.status)}</span></td><td>{batch.succeeded} succeeded · {batch.rejected} rejected · {batch.pending} pending · {batch.notRun} not run</td></tr>)}</tbody></table></div></div>{props.batches?.pageInfo.hasNextPage ? <div className="card-footer"><NextButton cursor={props.batches.pageInfo.endCursor} label="Next global batch page" onNext={props.onNextBatches} /></div> : null}</section>
      {props.batch ? <BatchDetailCard detail={props.batch} onNext={props.onNextBatchItems} /> : null}

      <p className="small text-body-secondary mb-0">Viewing latest available projections for <strong>{project.name ?? project.id}</strong> in <code>{project.scope}</code>. Projection freshness never gates availability.</p>
      <div className="d-flex flex-wrap gap-2"><Link className="btn btn-outline-primary" to={`/projects/${project.id}/coordination`}>View coordination</Link><Link className="btn btn-outline-primary" to={`/projects/${project.id}/resources`}>View resources</Link><Link className="btn btn-outline-primary" to={`/projects/${project.id}/knowledge`}>View knowledge</Link><Link className="btn btn-outline-primary" to={`/projects/${project.id}/governance`}>View governance</Link><Link className="btn btn-outline-secondary" to={`/projects?scope=${encodeURIComponent(project.scope)}`}>Back to project catalog</Link></div>
    </div>
  );
}
