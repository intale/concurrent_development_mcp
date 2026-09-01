import { Link } from "react-router-dom";
import type {
  CommandReceipt,
  CommandReceiptPage,
  GovernanceAgentChoice,
  GovernanceDecision,
  GovernanceGuidance,
  ProjectGovernance
} from "./project-governance-model.js";
import { badgeClass, humanized } from "./project-governance-model.js";

export interface ProjectGovernanceViewProps {
  readonly browser: ProjectGovernance | null;
  readonly choice: GovernanceAgentChoice | null;
  readonly decision: GovernanceDecision | null;
  readonly errorMessage: string | null;
  readonly guidance: GovernanceGuidance | null;
  readonly hrefForChoice: (choiceId: string) => string;
  readonly hrefForDecision: (decisionId: string) => string;
  readonly hrefForGuidance: (messageId: string) => string;
  readonly hrefForReceipt: (commandId: string) => string;
  readonly loading: boolean;
  readonly onNextChoices: (cursor: string) => void;
  readonly onNextDecisions: (cursor: string) => void;
  readonly onNextGuidance: (cursor: string) => void;
  readonly onNextImpacts: (cursor: string) => void;
  readonly onNextInterpretations: (cursor: string) => void;
  readonly onNextReceipts: (cursor: string) => void;
  readonly onNextSelectedChoiceImpacts: (cursor: string) => void;
  readonly onRetry: () => void;
  readonly receipt: CommandReceipt | null;
  readonly receipts: CommandReceiptPage | null;
  readonly refreshing: boolean;
}

function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}

function optional(value: string | null | undefined): string {
  return value || "—";
}

function StringList({ values }: { readonly values: readonly string[] | null }) {
  if (!values?.length) return <span className="text-body-secondary">—</span>;
  return <>{values.map((value) => <span className="badge text-bg-secondary me-1" key={value}>{value}</span>)}</>;
}

function PageButton({
  cursor,
  label,
  onNext
}: {
  readonly cursor: string | null;
  readonly label: string;
  readonly onNext: (cursor: string) => void;
}) {
  return cursor ? <button className="btn btn-outline-primary" onClick={() => onNext(cursor)} type="button">{label}</button> : null;
}

function DecisionDetail({ detail }: { readonly detail: GovernanceDecision }) {
  const { decision } = detail;
  return (
    <section aria-labelledby="decision-detail-heading" className="card card-outline card-primary">
      <div className="card-header d-flex justify-content-between align-items-center gap-3">
        <h2 className="card-title" id="decision-detail-heading">Decision · {decision.id}</h2>
        <span className={`badge ${badgeClass(decision.policyStatus)}`}>{humanized(decision.policyStatus)}</span>
      </div>
      <div className="card-body vstack gap-3">
        <div className="row g-3">
          <div className="col-12 col-lg-6">
            <h3 className="h6">Policy</h3>
            <dl className="row mb-0">
              <dt className="col-sm-4">Topic</dt><dd className="col-sm-8"><code>{decision.topicId}</code></dd>
              <dt className="col-sm-4">Statement</dt><dd className="col-sm-8">{humanized(decision.statementKind)} · {decision.modality} {decision.effect}</dd>
              <dt className="col-sm-4">Value</dt><dd className="col-sm-8">{decision.value.name ?? decision.value.items?.join(", ") ?? decision.value.action ?? decision.value.targetId ?? "—"}<div className="small text-body-secondary">{decision.value.schema}</div></dd>
              <dt className="col-sm-4">Enforcement</dt><dd className="col-sm-8">{humanized(decision.enforcement.level)} · {humanized(decision.enforcement.onViolation)}<div className="small text-body-secondary">{humanized(decision.enforcement.retroactivity)}</div></dd>
            </dl>
          </div>
          <div className="col-12 col-lg-6">
            <h3 className="h6">Provenance</h3>
            <dl className="row mb-0">
              <dt className="col-sm-4">Membership</dt><dd className="col-sm-8"><StringList values={detail.membershipBases} /></dd>
              <dt className="col-sm-4">Authority</dt><dd className="col-sm-8">{decision.authority.actorId} · {decision.authority.role}</dd>
              <dt className="col-sm-4">Recorded by</dt><dd className="col-sm-8">{decision.recordedBy.kind} · {decision.recordedBy.id}</dd>
              <dt className="col-sm-4">Current event</dt><dd className="col-sm-8">{decision.currentEvent.type} · revision {decision.currentEvent.streamRevision}<div><code>{decision.currentEvent.id}</code></div></dd>
              <dt className="col-sm-4">Definition</dt><dd className="col-sm-8"><code>{decision.definitionDigest}</code></dd>
            </dl>
          </div>
        </div>
        <div>
          <h3 className="h6">Scope and conditions</h3>
          <p className="mb-1">Repositories: <StringList values={decision.scope.repositoryIds} /></p>
          <p className="mb-1">Coordination: {optional(decision.scope.changeSetId)} · {optional(decision.scope.workItemId)} · {optional(decision.scope.attemptId)}</p>
          <p className="mb-1">Paths: <StringList values={decision.scope.pathSelectors} /></p>
          <p className="mb-0">Conditions: <StringList values={[...decision.conditions.phases, ...decision.conditions.languages, ...decision.conditions.tags]} /></p>
        </div>
        {decision.rationaleSummary ? <div className="alert alert-secondary mb-0"><strong>Rationale:</strong> {decision.rationaleSummary}</div> : null}
        {decision.correctionCount > 0 ? <div className="alert alert-warning mb-0"><strong>{decision.correctionCount} correction(s):</strong> {optional(decision.correctionSummary)}</div> : null}
      </div>
      <div className="card-footer small text-body-secondary">Recorded {formatted(decision.recordedAt)} · current {formatted(decision.currentAt)}</div>
    </section>
  );
}

function GuidanceDetail({
  detail,
  onNext
}: {
  readonly detail: GovernanceGuidance;
  readonly onNext: (cursor: string) => void;
}) {
  return (
    <section aria-labelledby="guidance-detail-heading" className="card card-outline card-info">
      <div className="card-header"><h2 className="card-title" id="guidance-detail-heading">Guidance · {detail.guidance.id}</h2></div>
      <div className="card-body vstack gap-3">
        <blockquote className="blockquote border-start border-4 border-info ps-3 mb-0"><p>{detail.guidance.text}</p><footer className="blockquote-footer mb-0">{detail.guidance.actor.kind} · {detail.guidance.actor.id} · {formatted(detail.guidance.recordedAt)}</footer></blockquote>
        <p className="small text-body-secondary mb-0">Source {humanized(detail.guidance.source)} · conversation <code>{detail.guidance.conversationId}</code></p>
        <div>
          <h3 className="h6">Interpretations</h3>
          <div className="vstack gap-2">
            {detail.interpretations.nodes.length === 0 ? <p className="text-body-secondary mb-0">No interpretation facts are available.</p> : detail.interpretations.nodes.map((item) => (
              <article className="border rounded p-3" key={item.id}>
                <div className="d-flex flex-wrap justify-content-between gap-2"><strong>{item.topicId}</strong><span className={`badge ${badgeClass(item.lifecycleStatus)}`}>{humanized(item.lifecycleStatus)}</span></div>
                <p className="mb-1">{item.modality ?? "—"} {item.effect ?? "—"} · {item.value.name ?? item.value.items?.join(", ") ?? "—"}</p>
                <p className="small text-body-secondary mb-1">Assessment: {humanized(item.assessmentStatus)} · revision fact {item.id}</p>
                {item.sourceSpanText ? <p className="mb-1"><strong>Source span:</strong> {item.sourceSpanText}</p> : null}
                <StringList values={item.assessmentReasons} />
                {item.clarificationQuestions.map((question) => <div className="alert alert-warning mt-2 mb-0" key={`${item.id}:${question.field}`}><strong>{question.field}:</strong> {question.prompt}<div className="small">{question.options.join(" · ")}</div></div>)}
              </article>
            ))}
          </div>
        </div>
      </div>
      {detail.interpretations.pageInfo.hasNextPage ? <div className="card-footer"><PageButton cursor={detail.interpretations.pageInfo.endCursor} label="Next interpretations page" onNext={onNext} /></div> : null}
    </section>
  );
}

function ChoiceDetail({
  detail,
  onNext
}: {
  readonly detail: GovernanceAgentChoice;
  readonly onNext: (cursor: string) => void;
}) {
  const { choice } = detail;
  return (
    <section aria-labelledby="choice-detail-heading" className="card card-outline card-warning">
      <div className="card-header d-flex justify-content-between align-items-center gap-3"><h2 className="card-title" id="choice-detail-heading">AgentChoice · {choice.id}</h2><span className={`badge ${badgeClass(choice.observationStatus)}`}>{humanized(choice.observationStatus)}</span></div>
      <div className="card-body vstack gap-3">
        <div className="row g-3">
          <div className="col-12 col-lg-6"><h3 className="h6">Selected option</h3><p className="fs-5 mb-1">{choice.selected.summary}</p><code>{choice.selected.id}</code><p className="mt-2 mb-0">{choice.reasonSummary}</p></div>
          <div className="col-12 col-lg-6"><h3 className="h6">Context</h3><p className="mb-1"><code>{choice.context.workItemId}</code> · <code>{choice.context.attemptId}</code></p><p className="mb-1">{choice.context.phase} · {choice.context.language} · {choice.context.agentRole}</p><StringList values={choice.context.paths} /></div>
        </div>
        <div><h3 className="h6">Alternatives</h3><ul className="mb-0">{choice.alternatives.map((option) => <li key={option.id}>{option.summary} (<code>{option.id}</code>)</li>)}</ul></div>
        <div className="alert alert-secondary mb-0"><strong>Assessment:</strong> {optional(choice.assessmentBasis)}<div><StringList values={choice.assessmentDecisionIds} /></div>{choice.assessmentWarnings.map((warning) => <div key={warning}>{warning}</div>)}</div>
        {choice.invalidationReason ? <div className="alert alert-danger mb-0"><strong>Invalidated:</strong> {choice.invalidationReason} · {formatted(choice.invalidatedAt)}</div> : null}
        <h3 className="h6 mb-0">Decision impacts</h3>
        <div className="table-responsive"><table aria-label="Selected AgentChoice impacts" className="table table-sm table-hover align-middle mb-0"><thead><tr><th>Decision</th><th>Outcome</th><th>Before</th><th>After</th><th>Assessed</th></tr></thead><tbody>
          {detail.impacts.nodes.length === 0 ? <tr><td className="text-center" colSpan={5}>No impact assessments.</td></tr> : detail.impacts.nodes.map((impact) => <tr key={impact.assessmentId}><td><code>{impact.decisionId}</code><div className="small">{humanized(impact.decisionChangeKind)}</div></td><td><span className={`badge ${badgeClass(impact.outcome)}`}>{humanized(impact.outcome)}</span><div className="small">{humanized(impact.reason)}</div></td><td>{humanized(impact.beforeStatus)}<div className="small">{humanized(impact.beforeBasis)}</div></td><td>{humanized(impact.afterStatus)}<div className="small">{humanized(impact.afterBasis)}</div></td><td>{formatted(impact.assessedAt)}</td></tr>)}
        </tbody></table></div>
      </div>
      {detail.impacts.pageInfo.hasNextPage ? <div className="card-footer"><PageButton cursor={detail.impacts.pageInfo.endCursor} label="Next selected-choice impacts page" onNext={onNext} /></div> : null}
    </section>
  );
}

function ReceiptDetail({ receipt }: { readonly receipt: CommandReceipt }) {
  return (
    <section aria-labelledby="receipt-detail-heading" className="card card-outline card-secondary">
      <div className="card-header"><h2 className="card-title" id="receipt-detail-heading">Command receipt · {receipt.commandId}</h2></div>
      <div className="card-body vstack gap-3">
        <div><span className={`badge ${badgeClass(receipt.status)}`}>{humanized(receipt.status)}</span> <strong>{receipt.toolName}</strong> · {receipt.summary}</div>
        <dl className="row mb-0"><dt className="col-sm-3">Receipt</dt><dd className="col-sm-9"><code>{receipt.receipt}</code></dd><dt className="col-sm-3">Completed</dt><dd className="col-sm-9">{formatted(receipt.completedAt)}</dd><dt className="col-sm-3">Next tools</dt><dd className="col-sm-9"><StringList values={receipt.nextActionTools} /></dd><dt className="col-sm-3">Warnings</dt><dd className="col-sm-9"><StringList values={receipt.warnings} /></dd></dl>
        <div><h3 className="h6">Emitted event facts</h3><div className="list-group">{receipt.emittedEvents.map((event) => <div className="list-group-item" key={event.id}><strong>{event.type}</strong> · <code>{event.streamContext}/{event.streamName}/{event.streamId}</code> · revision {event.streamRevision}<div className="small text-body-secondary">{event.id}</div></div>)}</div></div>
      </div>
    </section>
  );
}

export function ProjectGovernanceView(props: ProjectGovernanceViewProps) {
  if (props.loading && !props.browser) return <div className="card"><div className="card-body d-flex align-items-center gap-3" role="status"><span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" /><span>Loading project governance…</span></div></div>;
  if (props.errorMessage && !props.browser) return <div className="alert alert-danger" role="alert"><h2 className="h5">Project governance could not be loaded</h2><p>{props.errorMessage}</p><button className="btn btn-outline-light btn-sm" onClick={props.onRetry} type="button">Retry</button></div>;
  if (!props.browser) return <div className="alert alert-warning" role="status">This project is not available in the latest projection.</div>;

  const { choices, decisions, guidance, impacts, project } = props.browser;
  return (
    <div className="vstack gap-4">
      {props.errorMessage ? <div className="alert alert-warning" role="alert">The last available governance view remains visible. {props.errorMessage}<button className="btn btn-outline-dark btn-sm ms-3" onClick={props.onRetry} type="button">Retry refresh</button></div> : null}
      {props.refreshing ? <div className="alert alert-info mb-0" role="status">Refreshing latest available governance facts…</div> : null}

      <div aria-label="Governance summary" className="row g-3">
        <div className="col-6 col-xl-3"><div className="small-box text-bg-primary"><div className="inner"><h2>{decisions.nodes.length}</h2><p>Decisions on page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-signpost-split" /></span></div></div>
        <div className="col-6 col-xl-3"><div className="small-box text-bg-info"><div className="inner"><h2>{guidance.nodes.length}</h2><p>Guidance facts on page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-chat-square-text" /></span></div></div>
        <div className="col-6 col-xl-3"><div className="small-box text-bg-warning"><div className="inner"><h2>{choices.nodes.length}</h2><p>AgentChoices on page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-ui-checks-grid" /></span></div></div>
        <div className="col-6 col-xl-3"><div className="small-box text-bg-secondary"><div className="inner"><h2>{impacts.nodes.length}</h2><p>Impacts on page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-lightning" /></span></div></div>
      </div>

      <section aria-labelledby="decisions-heading" className="card card-outline card-primary"><div className="card-header"><h2 className="card-title" id="decisions-heading">Decisions</h2></div><div className="card-body p-0"><div className="table-responsive"><table aria-label="Project Decisions" className="table table-hover align-middle mb-0"><thead className="table-light"><tr><th>Decision</th><th>Policy</th><th>Scope basis</th><th>Current</th></tr></thead><tbody>
        {decisions.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={4}>No Decisions match these filters.</td></tr> : decisions.nodes.map((item) => <tr key={item.id}><td><Link className="fw-semibold" to={props.hrefForDecision(item.id)}>{item.topicId}</Link><div><code>{item.id}</code></div><div className="small text-body-secondary">{item.modality} {item.effect} · {item.value.name ?? item.value.items?.join(", ") ?? item.value.action ?? "—"}</div></td><td><span className={`badge ${badgeClass(item.policyStatus)}`}>{humanized(item.policyStatus)}</span><div className="small mt-1">{humanized(item.statementKind)}</div></td><td>{item.scope.attemptId ? "Attempt" : item.scope.workItemId ? "WorkItem" : item.scope.changeSetId ? "ChangeSet" : "Repository"}</td><td className="text-nowrap">{formatted(item.currentAt)}</td></tr>)}
      </tbody></table></div></div>{decisions.pageInfo.hasNextPage ? <div className="card-footer"><PageButton cursor={decisions.pageInfo.endCursor} label="Next Decisions page" onNext={props.onNextDecisions} /></div> : null}</section>

      {props.decision ? <DecisionDetail detail={props.decision} /> : null}

      <section aria-labelledby="guidance-heading" className="card card-outline card-info"><div className="card-header"><h2 className="card-title" id="guidance-heading">Guidance</h2></div><div className="card-body"><div className="list-group">{guidance.nodes.length === 0 ? <span className="list-group-item text-body-secondary">No guidance facts match these filters.</span> : guidance.nodes.map((item) => <Link className="list-group-item list-group-item-action" key={item.id} to={props.hrefForGuidance(item.id)}><div className="d-flex justify-content-between gap-3"><strong>{item.excerpt}</strong><span className="badge text-bg-info">{humanized(item.source)}</span></div><div className="small text-body-secondary mt-1"><code>{item.id}</code> · {item.actor.kind}/{item.actor.id} · {formatted(item.recordedAt)}</div></Link>)}</div></div>{guidance.pageInfo.hasNextPage ? <div className="card-footer"><PageButton cursor={guidance.pageInfo.endCursor} label="Next guidance page" onNext={props.onNextGuidance} /></div> : null}</section>

      {props.guidance ? <GuidanceDetail detail={props.guidance} onNext={props.onNextInterpretations} /> : null}

      <section aria-labelledby="choices-heading" className="card card-outline card-warning"><div className="card-header"><h2 className="card-title" id="choices-heading">AgentChoices</h2></div><div className="card-body p-0"><div className="table-responsive"><table aria-label="Project AgentChoices" className="table table-hover align-middle mb-0"><thead className="table-light"><tr><th>Choice</th><th>Selected</th><th>Status</th><th>Coordination</th></tr></thead><tbody>
        {choices.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={4}>No AgentChoices match these filters.</td></tr> : choices.nodes.map((item) => <tr key={item.id}><td><Link className="fw-semibold" to={props.hrefForChoice(item.id)}>{humanized(item.choiceType)}</Link><div><code>{item.id}</code></div><div className="small text-body-secondary">{item.reasonSummary}</div></td><td>{item.selected.summary}<div><code>{item.selected.id}</code></div></td><td><span className={`badge ${badgeClass(item.observationStatus)}`}>{humanized(item.observationStatus)}</span></td><td><code>{item.context.workItemId}</code><div className="small text-body-secondary">{item.context.attemptId}</div></td></tr>)}
      </tbody></table></div></div>{choices.pageInfo.hasNextPage ? <div className="card-footer"><PageButton cursor={choices.pageInfo.endCursor} label="Next AgentChoices page" onNext={props.onNextChoices} /></div> : null}</section>

      {props.choice ? <ChoiceDetail detail={props.choice} onNext={props.onNextSelectedChoiceImpacts} /> : null}

      <section aria-labelledby="impacts-heading" className="card card-outline card-secondary"><div className="card-header"><h2 className="card-title" id="impacts-heading">Project decision impacts</h2></div><div className="card-body p-0"><div className="table-responsive"><table aria-label="Project AgentChoice impacts" className="table table-hover align-middle mb-0"><thead className="table-light"><tr><th>Choice</th><th>Decision</th><th>Outcome</th><th>Transition</th><th>Assessed</th></tr></thead><tbody>
        {impacts.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={5}>No decision-impact assessments match these filters.</td></tr> : impacts.nodes.map((item) => <tr key={item.assessmentId}><td><Link to={props.hrefForChoice(item.choiceId)}><code>{item.choiceId}</code></Link><div className="small">{item.attemptId}</div></td><td><code>{item.decisionId}</code><div className="small">{humanized(item.decisionChangeKind)}</div></td><td><span className={`badge ${badgeClass(item.outcome)}`}>{humanized(item.outcome)}</span><div className="small">{humanized(item.reason)}</div></td><td>{humanized(item.beforeStatus)} → {humanized(item.afterStatus)}</td><td>{formatted(item.assessedAt)}</td></tr>)}
      </tbody></table></div></div>{impacts.pageInfo.hasNextPage ? <div className="card-footer"><PageButton cursor={impacts.pageInfo.endCursor} label="Next impacts page" onNext={props.onNextImpacts} /></div> : null}</section>

      <section aria-labelledby="receipts-heading" className="card card-outline card-dark"><div className="card-header"><h2 className="card-title" id="receipts-heading">Global command receipts</h2></div><div className="card-body"><div className="alert alert-secondary"><strong>Global audit view.</strong> Receipts do not have inferred project attribution and may describe commands from any project.</div><div className="table-responsive"><table aria-label="Global command receipts" className="table table-hover align-middle mb-0"><thead className="table-light"><tr><th>Command</th><th>Tool</th><th>Status</th><th>Summary</th><th>Completed</th></tr></thead><tbody>
        {!props.receipts || props.receipts.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={5}>No global command receipts match this filter.</td></tr> : props.receipts.nodes.map((item) => <tr key={item.commandId}><td><Link to={props.hrefForReceipt(item.commandId)}><code>{item.commandId}</code></Link></td><td>{item.toolName}</td><td><span className={`badge ${badgeClass(item.status)}`}>{humanized(item.status)}</span></td><td>{item.summary}</td><td>{formatted(item.completedAt)}</td></tr>)}
      </tbody></table></div></div>{props.receipts?.pageInfo.hasNextPage ? <div className="card-footer"><PageButton cursor={props.receipts.pageInfo.endCursor} label="Next global receipts page" onNext={props.onNextReceipts} /></div> : null}</section>

      {props.receipt ? <ReceiptDetail receipt={props.receipt} /> : null}

      <p className="small text-body-secondary mb-0">Viewing latest available projections for <strong>{project.name ?? project.id}</strong> in <code>{project.scope}</code>. Projection freshness never gates availability.</p>
      <div className="d-flex flex-wrap gap-2"><Link className="btn btn-outline-primary" to={`/projects/${project.id}/coordination`}>View coordination</Link><Link className="btn btn-outline-primary" to={`/projects/${project.id}/resources`}>View resources</Link><Link className="btn btn-outline-primary" to={`/projects/${project.id}/knowledge`}>View knowledge</Link><Link className="btn btn-outline-secondary" to={`/projects?scope=${encodeURIComponent(project.scope)}`}>Back to project catalog</Link></div>
    </div>
  );
}
