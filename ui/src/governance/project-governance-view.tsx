import { useEffect, useRef } from "react";
import type { RefObject } from "react";
import { DataTable, TextPreview, Timestamp } from "../data-table.js";
import { ContextLink as Link } from "../navigation.js";
import { CopyIdentifier } from "../copy-identifier.js";
import { RetryRefresh } from "../retry-refresh.js";
import type {
  ChoiceConnection,
  ChoiceDetail,
  DecisionConnection,
  DecisionDetail,
  GuidanceConnection,
  GuidanceDetail,
  ImpactConnection,
  ImpactDetail,
} from "./project-governance-model.js";
import { badgeClass, humanized } from "./project-governance-model.js";

export function useGovernanceHeading(title: string, focusKey: string): RefObject<HTMLHeadingElement> {
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
        announcementLabel="Governance view"
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
      <button className="btn btn-outline-secondary" disabled={!canPrevious} onClick={onPrevious} type="button">Previous</button>
      <button className="btn btn-outline-primary" disabled={!nextCursor} onClick={() => nextCursor && onNext(nextCursor)} type="button">Next</button>
    </nav>
  );
}

export function DecisionTable({ connection, hrefFor }: {
  readonly connection: DecisionConnection;
  readonly hrefFor: (id: string) => string;
}) {
  return <DataTable caption="Project Decisions" rows={connection.nodes} rowKey={(decision) => decision.id} emptyMessage="No Decisions match these filters." columns={[
    { key: "topic", label: "Topic", render: (decision) => <><Link to={hrefFor(decision.id)}>{decision.topicId}</Link><div><code>{decision.id}</code></div><TextPreview text={decisionValue(decision.value)} /></> },
    { key: "status", label: "Status", render: (decision) => <span className={`badge ${badgeClass(decision.policyStatus)}`}>{humanized(decision.policyStatus)}</span> },
    { key: "effect", label: "Modality/effect", render: (decision) => <>{decision.modality} {humanized(decision.effect)} · {decisionValue(decision.value)}</> },
    { key: "scope", label: "Scope basis", render: (decision) => scopeBasis(decision.scope) },
    { key: "current", label: "Current", render: (decision) => <Timestamp value={decision.currentAt} /> }
  ]} />;
}

export function GuidanceTable({ connection, hrefFor }: {
  readonly connection: GuidanceConnection;
  readonly hrefFor: (id: string) => string;
}) {
  return <DataTable caption="Project Guidance" rows={connection.nodes} rowKey={(guidance) => guidance.id} emptyMessage="No Guidance matches this source." columns={[
    { key: "excerpt", label: "Guidance excerpt", render: (guidance) => <><Link to={hrefFor(guidance.id)}><TextPreview text={guidance.excerpt} /></Link><div><code>{guidance.id}</code></div></> },
    { key: "source", label: "Source", render: (guidance) => <span className="badge text-bg-info">{humanized(guidance.source)}</span> },
    { key: "actor", label: "Actor", render: (guidance) => `${guidance.actor.kind}/${guidance.actor.id}` },
    { key: "recorded", label: "Recorded", render: (guidance) => <Timestamp value={guidance.recordedAt} /> }
  ]} />;
}

export function ChoiceTable({ connection, hrefFor }: {
  readonly connection: ChoiceConnection;
  readonly hrefFor: (id: string) => string;
}) {
  return <DataTable caption="Project AgentChoices" rows={connection.nodes} rowKey={(choice) => choice.id} emptyMessage="No AgentChoices match these filters." columns={[
    { key: "choice", label: "Choice", render: (choice) => <><Link to={hrefFor(choice.id)}>{humanized(choice.choiceType)}</Link><div><code>{choice.id}</code></div></> },
    { key: "status", label: "Status", render: (choice) => <span className={`badge ${badgeClass(choice.observationStatus)}`}>{humanized(choice.observationStatus)}</span> },
    { key: "selected", label: "Selected value/alternative", render: (choice) => <>{choice.selected.summary} <code>{choice.selected.id}</code><p className="mb-0">{choice.reasonSummary}</p></> },
    { key: "agent", label: "Agent/Attempt", render: (choice) => <>WorkItem <code>{choice.context.workItemId}</code> · Attempt <code>{choice.context.attemptId}</code></> },
    { key: "recorded", label: "Recorded", render: (choice) => <Timestamp value={choice.recordedAt} /> }
  ]} />;
}

export function ImpactTable({ connection, hrefFor }: {
  readonly connection: ImpactConnection;
  readonly hrefFor: (id: string) => string;
}) {
  return <DataTable caption="Project decision impacts" rows={connection.nodes} rowKey={(impact) => impact.assessmentId} emptyMessage="No decision impacts match this outcome." columns={[
    { key: "choice", label: "Choice", render: (impact) => <><Link to={hrefFor(impact.assessmentId)}><code>{impact.choiceId}</code></Link><div><code>{impact.assessmentId}</code></div></> },
    { key: "outcome", label: "Outcome", render: (impact) => <span className={`badge ${badgeClass(impact.outcome)}`}>{humanized(impact.outcome)}</span> },
    { key: "decision", label: "Decision", render: (impact) => <><code>{impact.decisionId}</code><div>{humanized(impact.decisionChangeKind)}</div></> },
    { key: "reasons", label: "Reasons/evidence", render: (impact) => <>{humanized(impact.beforeStatus)} → {humanized(impact.afterStatus)} · {humanized(impact.reason)}</> },
    { key: "assessed", label: "Assessed", render: (impact) => <Timestamp value={impact.assessedAt} /> }
  ]} />;
}

export function DecisionDetailCard({ detail, backTo }: {
  readonly detail: DecisionDetail;
  readonly backTo: string;
}) {
  const { decision } = detail;
  return (
    <article className="card card-outline card-primary">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2">
        <h3 className="card-title text-break">{decision.topicId}</h3>
        <span className={`badge ${badgeClass(decision.policyStatus)}`}>{humanized(decision.policyStatus)}</span>
      </div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Decision ID" value={decision.id} />
        <section><h4 className="h6">Decision</h4><p className="mb-1">{decision.modality} {humanized(decision.effect)} · {decisionValue(decision.value)}</p><p className="mb-0">{decision.rationaleSummary ?? "No rationale summary was recorded."}</p></section>
        {decision.correctionSummary ? <div className="alert alert-info mb-0"><strong>Current correction:</strong> {decision.correctionSummary}</div> : null}
        <DetailGroup title="Scope and conditions" rows={[
          ["Membership basis", detail.membershipBases.join(", ")],
          ["Repositories", decision.scope.repositoryIds.join(", ")],
          ["ChangeSet", decision.scope.changeSetId],
          ["WorkItem", decision.scope.workItemId],
          ["Attempt", decision.scope.attemptId],
          ["Paths", decision.scope.pathSelectors.join(", ") || "Any"],
          ["Phases", decision.conditions.phases.join(", ") || "Any"],
          ["Languages", decision.conditions.languages.join(", ") || "Any"]
        ]} />
        <DetailGroup title="Policy" rows={[
          ["Statement", humanized(decision.statementKind)],
          ["Authority", `${decision.authority.role} · ${decision.authority.actorId}`],
          ["Enforcement", `${humanized(decision.enforcement.level)} · ${humanized(decision.enforcement.onViolation)}`],
          ["Retroactivity", humanized(decision.enforcement.retroactivity)]
        ]} />
        <DetailGroup title="Lifecycle evidence" rows={[
          ["Decision", decision.id],
          ["Interpretation", decision.interpretationId],
          ["Source message", decision.sourceMessageId],
          ["Definition digest", decision.definitionDigest],
          ["Recorded", `${formatted(decision.recordedAt)} by ${decision.recordedBy.kind}/${decision.recordedBy.id}`],
          ["Current", `${formatted(decision.currentAt)} by ${decision.currentBy.kind}/${decision.currentBy.id}`],
          ["Current event", `${decision.currentEvent.type} · ${decision.currentEvent.id}`]
        ]} />
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to Decisions</Link>
      </div>
    </article>
  );
}

export function GuidanceDetailCard({ detail, backTo }: {
  readonly detail: GuidanceDetail;
  readonly backTo: string;
}) {
  const { guidance } = detail;
  return (
    <article className="card card-outline card-info">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title">Guidance</h3><span className="badge text-bg-info">{humanized(guidance.source)}</span></div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Guidance ID" value={guidance.id} />
        <blockquote className="blockquote mb-0"><p className="text-break">{guidance.text}</p><footer className="blockquote-footer mb-0">{guidance.actor.kind}/{guidance.actor.id} · {formatted(guidance.recordedAt)}</footer></blockquote>
        <DetailGroup title="Anchors" rows={[
          ["Repositories", guidance.anchors.repositoryIds.join(", ")],
          ["ChangeSet", guidance.anchors.changeSetId],
          ["WorkItem", guidance.anchors.workItemId],
          ["Attempt", guidance.anchors.attemptId],
          ["Conversation", guidance.conversationId],
          ["Message", guidance.id]
        ]} />
        <section aria-labelledby="guidance-interpretations-heading"><h4 className="h6" id="guidance-interpretations-heading">Interpretations</h4><div className="vstack gap-3">
          <DataTable caption="Interpretations" rows={detail.interpretations.nodes} rowKey={(row) => row.id} emptyMessage="No interpretation proposals were projected." columns={[
            { key: "topic", label: "Topic", render: (row) => <><strong>{row.topicId}</strong><div>{row.modality ?? "—"} {humanized(row.effect ?? "unspecified")} · {decisionValue(row.value)}</div>{row.sourceSpanText ? <div>Source span: “{row.sourceSpanText}”</div> : null}</> },
            { key: "lifecycle", label: "Lifecycle", render: (row) => <span className="badge text-bg-secondary">{humanized(row.lifecycleStatus)}</span> },
            { key: "assessment", label: "Assessment", render: (row) => `${humanized(row.assessmentStatus)} · ${row.assessmentReasons.join(", ") || "No reasons"}` }
          ]} />
        </div></section>
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to Guidance</Link>
      </div>
    </article>
  );
}

export function ChoiceDetailCard({ detail, backTo, impactHref }: {
  readonly detail: ChoiceDetail;
  readonly backTo: string;
  readonly impactHref: (id: string) => string;
}) {
  const { choice } = detail;
  return (
    <article className="card card-outline card-warning">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title">{humanized(choice.choiceType)}</h3><span className={`badge ${badgeClass(choice.observationStatus)}`}>{humanized(choice.observationStatus)}</span></div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="AgentChoice ID" value={choice.id} />
        <section><h4 className="h6">Selected option</h4><p className="h5 mb-1">{choice.selected.summary}</p><code>{choice.selected.id}</code><p className="mt-2 mb-0">{choice.reasonSummary}</p></section>
        <section><h4 className="h6">Alternatives considered</h4><DataTable caption="Alternatives considered" rows={choice.alternatives} rowKey={(row) => row.id} emptyMessage="No alternatives recorded." columns={[{ key: "summary", label: "Alternative", render: (row) => row.summary }, { key: "id", label: "Identifier", render: (row) => <code>{row.id}</code> }]} /></section>
        <DetailGroup title="Coordination context" rows={[
          ["Repository", choice.context.repositoryId],
          ["ChangeSet", choice.context.changeSetId],
          ["WorkItem", choice.context.workItemId],
          ["Attempt", choice.context.attemptId],
          ["Phase", choice.context.phase],
          ["Language", choice.context.language],
          ["Paths", choice.context.paths.join(", ")]
        ]} />
        <DetailGroup title="Assessment and lifecycle" rows={[
          ["Basis", choice.assessmentBasis],
          ["Decision evidence", choice.assessmentDecisionIds.join(", ") || "None"],
          ["Warnings", choice.assessmentWarnings.join(", ") || "None"],
          ["Recorded", `${formatted(choice.recordedAt)} by ${choice.recordedBy.kind}/${choice.recordedBy.id}`],
          ["Accepted", choice.acceptedAt ? `${formatted(choice.acceptedAt)} by ${choice.acceptedBy?.kind}/${choice.acceptedBy?.id}` : null],
          ["Invalidated", choice.invalidatedAt ? `${formatted(choice.invalidatedAt)} · ${choice.invalidationReason ?? "No reason"}` : null]
        ]} />
        <section aria-labelledby="choice-impacts-heading"><h4 className="h6" id="choice-impacts-heading">Decision impacts</h4><DetailImpactTable connection={detail.impacts} hrefFor={impactHref} /></section>
        <Link className="btn btn-outline-secondary align-self-start" to={backTo}>Back to AgentChoices</Link>
      </div>
    </article>
  );
}

export function ImpactDetailCard({ detail, backTo, choiceHref, decisionHref }: {
  readonly detail: ImpactDetail;
  readonly backTo: string;
  readonly choiceHref: string;
  readonly decisionHref: string;
}) {
  const { impact } = detail;
  return (
    <article className="card card-outline card-secondary">
      <div className="card-header d-flex flex-wrap justify-content-between gap-2"><h3 className="card-title">Decision impact</h3><span className={`badge ${badgeClass(impact.outcome)}`}>{humanized(impact.outcome)}</span></div>
      <div className="card-body vstack gap-4">
        <CopyIdentifier label="Impact assessment ID" value={impact.assessmentId} />
        <section><h4 className="h6">Assessment</h4><p className="mb-1">{humanized(impact.reason)}</p><p className="text-body-secondary mb-0">Assessed {formatted(impact.assessedAt)} under {impact.policyVersion}</p></section>
        <div className="row g-3">
          <div className="col-12 col-lg-6"><div className="border rounded p-3 h-100"><h4 className="h6">Before</h4><div className={`badge ${badgeClass(impact.beforeStatus)}`}>{humanized(impact.beforeStatus)}</div><p className="mt-2 mb-1">{humanized(impact.beforeBasis)}</p><div className="small text-body-secondary">{impact.beforeReasonCodes.map(humanized).join(", ") || "No reason codes"}</div></div></div>
          <div className="col-12 col-lg-6"><div className="border rounded p-3 h-100"><h4 className="h6">After</h4><div className={`badge ${badgeClass(impact.afterStatus)}`}>{humanized(impact.afterStatus)}</div><p className="mt-2 mb-1">{humanized(impact.afterBasis)}</p><div className="small text-body-secondary">{impact.afterReasonCodes.map(humanized).join(", ") || "No reason codes"}</div></div></div>
        </div>
        <DetailGroup title="Evidence" rows={[
          ["Assessment", impact.assessmentId],
          ["AgentChoice", impact.choiceId],
          ["Attempt", impact.attemptId],
          ["Decision", impact.decisionId],
          ["Decision change", `${humanized(impact.decisionChangeKind)} · ${formatted(impact.decisionChangedAt)}`]
        ]} />
        <div className="d-flex flex-wrap gap-2"><Link className="btn btn-outline-primary" to={choiceHref}>View AgentChoice</Link><Link className="btn btn-outline-primary" to={decisionHref}>View Decision</Link><Link className="btn btn-outline-secondary" to={backTo}>Back to impacts</Link></div>
      </div>
    </article>
  );
}

function DetailImpactTable({ connection, hrefFor }: { readonly connection: ImpactConnection; readonly hrefFor: (id: string) => string }) {
  return <DataTable caption="Decision impacts" rows={connection.nodes} rowKey={(impact) => impact.assessmentId} emptyMessage="No decision impacts were projected." columns={[
    { key: "choice", label: "Choice", render: (impact) => <><Link to={hrefFor(impact.assessmentId)}><code>{impact.choiceId}</code></Link><div><code>{impact.assessmentId}</code></div></> },
    { key: "outcome", label: "Outcome", render: (impact) => <span className={`badge ${badgeClass(impact.outcome)}`}>{humanized(impact.outcome)}</span> },
    { key: "decision", label: "Decision", render: (impact) => <><code>{impact.decisionId}</code><div>{humanized(impact.decisionChangeKind)}</div></> },
    { key: "reasons", label: "Reasons/evidence", render: (impact) => <>{humanized(impact.beforeStatus)} → {humanized(impact.afterStatus)} · {humanized(impact.reason)}</> },
    { key: "assessed", label: "Assessed", render: (impact) => <Timestamp value={impact.assessedAt} /> }
  ]} />;
}

function DetailGroup({ title, rows }: {
  readonly title: string;
  readonly rows: ReadonlyArray<readonly [string, string | null | undefined]>;
}) {
  return (
    <section><h4 className="h6">{title}</h4><dl className="row mb-0">{rows.map(([label, value]) => <div className="col-12 col-lg-6" key={label}><dt>{label}</dt><dd className="text-break"><code>{value ?? "—"}</code></dd></div>)}</dl></section>
  );
}

function decisionValue(value: {
  readonly action?: string | null;
  readonly items?: readonly string[] | null;
  readonly name?: string | null;
  readonly targetId?: string | null;
  readonly targetKind?: string | null;
}): string {
  return value.name ?? value.items?.join(", ") ?? [value.action, value.targetKind, value.targetId].filter(Boolean).join(" ") ?? "—";
}

function scopeBasis(scope: {
  readonly attemptId?: string | null;
  readonly changeSetId?: string | null;
  readonly workItemId?: string | null;
}): string {
  if (scope.attemptId) return "Attempt";
  if (scope.workItemId) return "WorkItem";
  if (scope.changeSetId) return "ChangeSet";
  return "Repository";
}

function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}
