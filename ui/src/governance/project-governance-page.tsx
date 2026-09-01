import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useLocation, useParams, useSearchParams } from "react-router-dom";
import type {
  AgentChoiceImpactOutcome,
  AgentChoiceKind,
  AgentChoiceStatus,
  DecisionPolicyStatus,
  GuidanceSource
} from "../gql/graphql.js";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import {
  fetchGovernanceAgentChoice,
  fetchGovernanceAgentChoices,
  fetchGovernanceDecision,
  fetchGovernanceDecisionImpact,
  fetchGovernanceDecisionImpacts,
  fetchGovernanceDecisions,
  fetchGovernanceGuidance,
  fetchGovernanceGuidanceMessages
} from "./project-governance-api.js";
import type { ChoiceFilters, DecisionFilters, GuidanceFilters, ImpactFilters } from "./project-governance-api.js";
import {
  AGENT_CHOICE_KINDS,
  AGENT_CHOICE_STATUSES,
  applyFilters,
  DECISION_POLICY_STATUSES,
  detailLocation,
  GUIDANCE_SOURCES,
  IMPACT_OUTCOMES,
  listLocation,
  matching,
  nextPageParams,
  preserveCollection,
  preserveDetail,
  previousPageParams,
  safeGovernanceReturnTo
} from "./project-governance-model.js";
import {
  AvailableStale,
  ChoiceCards,
  ChoiceDetailCard,
  DecisionCards,
  DecisionDetailCard,
  GovernanceNavigation,
  GuidanceCards,
  GuidanceDetailCard,
  ImpactCards,
  ImpactDetailCard,
  InitialError,
  LoadingState,
  PaginationControls,
  useGovernanceHeading
} from "./project-governance-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectGovernanceDecisionsPage() {
  const { projectRef } = useProjectWorkspace();
  const { decisionId } = useParams<{ readonly decisionId?: string }>();
  return decisionId ? <DecisionPage decisionId={decisionId} projectRef={projectRef} /> : <DecisionsPage projectRef={projectRef} />;
}

export function ProjectGovernanceGuidancePage() {
  const { projectRef } = useProjectWorkspace();
  const { messageId } = useParams<{ readonly messageId?: string }>();
  return messageId ? <GuidancePage messageId={messageId} projectRef={projectRef} /> : <GuidanceListPage projectRef={projectRef} />;
}

export function ProjectGovernanceChoicesPage() {
  const { projectRef } = useProjectWorkspace();
  const { choiceId } = useParams<{ readonly choiceId?: string }>();
  return choiceId ? <ChoicePage choiceId={choiceId} projectRef={projectRef} /> : <ChoicesPage projectRef={projectRef} />;
}

export function ProjectGovernanceImpactsPage() {
  const { projectRef } = useProjectWorkspace();
  const { assessmentId } = useParams<{ readonly assessmentId?: string }>();
  return assessmentId ? <ImpactPage assessmentId={assessmentId} projectRef={projectRef} /> : <ImpactsPage projectRef={projectRef} />;
}

function DecisionsPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/governance/decisions`;
  const basePath = `/projects/${projectRef}/governance`;
  const topicId = searchParams.get("topic") ?? "";
  const policyStatus = matching<DecisionPolicyStatus>(searchParams.get("status"), DECISION_POLICY_STATUSES);
  const [draft, setDraft] = useState({ topic: topicId, status: policyStatus ?? "" });
  const after = searchParams.get("after");
  const headingRef = useGovernanceHeading("Project Decisions", "project-decisions");
  useEffect(() => { setDraft({ topic: topicId, status: policyStatus ?? "" }); }, [topicId, policyStatus]);

  const filters: DecisionFilters = { ...(topicId ? { topicId } : {}), ...(policyStatus ? { policyStatus } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-governance-decisions", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchGovernanceDecisions(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(previousData, previousQuery?.queryKey, projectRef, filterKey),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectDecisions ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <GovernanceNavigation basePath={basePath} />
      <PageHeading description="Review current coordination policy facts and their exact scope basis." headingRef={headingRef} title="Decisions" />
      <form aria-label="Decision filters" className="card card-body" onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, draft)); }}>
        <div className="row g-3 align-items-end">
          <div className="col-12 col-lg-7"><label className="form-label" htmlFor="decision-topic">Topic</label><input className="form-control" id="decision-topic" onChange={(event) => setDraft((value) => ({ ...value, topic: event.target.value }))} placeholder="testing.framework" value={draft.topic} /></div>
          <div className="col-12 col-sm-6 col-lg-3"><label className="form-label" htmlFor="decision-status">Policy status</label><select className="form-select" id="decision-status" onChange={(event) => setDraft((value) => ({ ...value, status: event.target.value as DecisionPolicyStatus | "" }))} value={draft.status}><option value="">All statuses</option>{DECISION_POLICY_STATUSES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>
          <FilterActions clear={() => setSearchParams({})} />
        </div>
      </form>
      <CollectionState connection={connection} errorMessage={errorMessage} label="Decisions" loading={query.isPending} retry={() => { void query.refetch(); }}>
        {connection ? <><DecisionCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
      </CollectionState>
    </div>
  );
}

function GuidanceListPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/governance/guidance`;
  const basePath = `/projects/${projectRef}/governance`;
  const source = matching<GuidanceSource>(searchParams.get("source"), GUIDANCE_SOURCES);
  const after = searchParams.get("after");
  const headingRef = useGovernanceHeading("Project Guidance", "project-guidance");
  const filters: GuidanceFilters = { ...(source ? { source } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-governance-guidance", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchGovernanceGuidanceMessages(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(previousData, previousQuery?.queryKey, projectRef, filterKey),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectGuidanceMessages ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <GovernanceNavigation basePath={basePath} />
      <PageHeading description="Read user guidance, its actors, anchors, and interpretation proposals." headingRef={headingRef} title="Guidance" />
      <form aria-label="Guidance filters" className="card card-body">
        <div className="row g-3 align-items-end"><div className="col-12 col-md-8"><label className="form-label" htmlFor="guidance-source">Source</label><select className="form-select" id="guidance-source" onChange={(event) => setSearchParams(applyFilters(searchParams, { source: event.target.value }))} value={source ?? ""}><option value="">All sources</option>{GUIDANCE_SOURCES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div><div className="col-12 col-md-4"><button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button></div></div>
      </form>
      <CollectionState connection={connection} errorMessage={errorMessage} label="Guidance" loading={query.isPending} retry={() => { void query.refetch(); }}>
        {connection ? <><GuidanceCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
      </CollectionState>
    </div>
  );
}

function ChoicesPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/governance/choices`;
  const basePath = `/projects/${projectRef}/governance`;
  const choiceType = matching<AgentChoiceKind>(searchParams.get("type"), AGENT_CHOICE_KINDS);
  const status = matching<AgentChoiceStatus>(searchParams.get("status"), AGENT_CHOICE_STATUSES);
  const after = searchParams.get("after");
  const headingRef = useGovernanceHeading("Project AgentChoices", "project-agent-choices");
  const filters: ChoiceFilters = { ...(choiceType ? { choiceType } : {}), ...(status ? { status } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-governance-choices", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchGovernanceAgentChoices(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(previousData, previousQuery?.queryKey, projectRef, filterKey),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectAgentChoices ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <GovernanceNavigation basePath={basePath} />
      <PageHeading description="Inspect agent-selected options, reasons, coordination context, and lifecycle." headingRef={headingRef} title="AgentChoices" />
      <form aria-label="AgentChoice filters" className="card card-body"><div className="row g-3 align-items-end">
        <div className="col-12 col-md-5"><label className="form-label" htmlFor="choice-type">Type</label><select className="form-select" id="choice-type" onChange={(event) => setSearchParams(applyFilters(searchParams, { type: event.target.value, status: status ?? "" }))} value={choiceType ?? ""}><option value="">All types</option>{AGENT_CHOICE_KINDS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>
        <div className="col-12 col-md-5"><label className="form-label" htmlFor="choice-status">Status</label><select className="form-select" id="choice-status" onChange={(event) => setSearchParams(applyFilters(searchParams, { type: choiceType ?? "", status: event.target.value }))} value={status ?? ""}><option value="">All statuses</option>{AGENT_CHOICE_STATUSES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div>
        <div className="col-12 col-md-2"><button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button></div>
      </div></form>
      <CollectionState connection={connection} errorMessage={errorMessage} label="AgentChoices" loading={query.isPending} retry={() => { void query.refetch(); }}>
        {connection ? <><ChoiceCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
      </CollectionState>
    </div>
  );
}

function ImpactsPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/governance/impacts`;
  const basePath = `/projects/${projectRef}/governance`;
  const outcome = matching<AgentChoiceImpactOutcome>(searchParams.get("outcome"), IMPACT_OUTCOMES);
  const after = searchParams.get("after");
  const headingRef = useGovernanceHeading("Project decision impacts", "project-decision-impacts");
  const filters: ImpactFilters = { ...(outcome ? { outcome } : {}) };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-governance-impacts", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchGovernanceDecisionImpacts(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(previousData, previousQuery?.queryKey, projectRef, filterKey),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectDecisionImpacts ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <GovernanceNavigation basePath={basePath} />
      <PageHeading description="Review how Decision changes affected previously recorded AgentChoices." headingRef={headingRef} title="Decision impacts" />
      <form aria-label="Decision impact filters" className="card card-body"><div className="row g-3 align-items-end"><div className="col-12 col-md-8"><label className="form-label" htmlFor="impact-outcome">Outcome</label><select className="form-select" id="impact-outcome" onChange={(event) => setSearchParams(applyFilters(searchParams, { outcome: event.target.value }))} value={outcome ?? ""}><option value="">All outcomes</option>{IMPACT_OUTCOMES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></div><div className="col-12 col-md-4"><button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button></div></div></form>
      <CollectionState connection={connection} errorMessage={errorMessage} label="Decision impacts" loading={query.isPending} retry={() => { void query.refetch(); }}>
        {connection ? <><ImpactCards connection={connection} hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
      </CollectionState>
    </div>
  );
}

function DecisionPage({ projectRef, decisionId }: { readonly projectRef: string; readonly decisionId: string }) {
  const [searchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/governance`;
  const listPath = `${basePath}/decisions`;
  const backTo = safeGovernanceReturnTo(searchParams.get("returnTo"), listPath, basePath);
  const headingRef = useGovernanceHeading("Decision detail", decisionId);
  const query = useQuery({ queryKey: ["project-governance-decision", projectRef, decisionId], queryFn: ({ signal }) => fetchGovernanceDecision(projectRef, decisionId, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, decisionId), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectDecision ?? null;
  return <DetailPage basePath={basePath} backLabel="Decisions" backTo={backTo} description="Current policy, scope, lifecycle, and event evidence." detail={detail} error={query.error} headingRef={headingRef} label="Decision detail" loading={query.isPending} retry={() => { void query.refetch(); }}>{detail ? <DecisionDetailCard backTo={backTo} detail={detail} /> : null}</DetailPage>;
}

function GuidancePage({ projectRef, messageId }: { readonly projectRef: string; readonly messageId: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/governance`;
  const listPath = `${basePath}/guidance`;
  const backTo = safeGovernanceReturnTo(searchParams.get("returnTo"), listPath, basePath);
  const after = searchParams.get("after");
  const headingRef = useGovernanceHeading("Guidance detail", messageId);
  const query = useQuery({ queryKey: ["project-governance-guidance-detail", projectRef, messageId, after], queryFn: ({ signal }) => fetchGovernanceGuidance(projectRef, messageId, after, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, messageId), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectGuidance ?? null;
  return <DetailPage basePath={basePath} backLabel="Guidance" backTo={backTo} description="Original guidance, anchors, actor, and interpretation proposals." detail={detail} error={query.error} headingRef={headingRef} label="Guidance detail" loading={query.isPending} retry={() => { void query.refetch(); }}>{detail ? <><GuidanceDetailCard backTo={backTo} detail={detail} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={detail.interpretations.pageInfo.hasNextPage ? detail.interpretations.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}</DetailPage>;
}

function ChoicePage({ projectRef, choiceId }: { readonly projectRef: string; readonly choiceId: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const location = useLocation();
  const basePath = `/projects/${projectRef}/governance`;
  const listPath = `${basePath}/choices`;
  const backTo = safeGovernanceReturnTo(searchParams.get("returnTo"), listPath, basePath);
  const after = searchParams.get("after");
  const headingRef = useGovernanceHeading("AgentChoice detail", choiceId);
  const query = useQuery({ queryKey: ["project-governance-choice", projectRef, choiceId, after], queryFn: ({ signal }) => fetchGovernanceAgentChoice(projectRef, choiceId, after, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, choiceId), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectAgentChoice ?? null;
  const currentLocation = `${location.pathname}${location.search}`;
  return <DetailPage basePath={basePath} backLabel="AgentChoices" backTo={backTo} description="Selected option, alternatives, assessment basis, context, and lifecycle." detail={detail} error={query.error} headingRef={headingRef} label="AgentChoice detail" loading={query.isPending} retry={() => { void query.refetch(); }}>{detail ? <><ChoiceDetailCard backTo={backTo} detail={detail} impactHref={(id) => detailLocation(`${basePath}/impacts`, id, currentLocation)} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={detail.impacts.pageInfo.hasNextPage ? detail.impacts.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}</DetailPage>;
}

function ImpactPage({ projectRef, assessmentId }: { readonly projectRef: string; readonly assessmentId: string }) {
  const [searchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/governance`;
  const listPath = `${basePath}/impacts`;
  const backTo = safeGovernanceReturnTo(searchParams.get("returnTo"), listPath, basePath);
  const headingRef = useGovernanceHeading("Decision impact detail", assessmentId);
  const query = useQuery({ queryKey: ["project-governance-impact", projectRef, assessmentId], queryFn: ({ signal }) => fetchGovernanceDecisionImpact(projectRef, assessmentId, signal), placeholderData: (data, previous) => preserveDetail(data, previous?.queryKey, projectRef, assessmentId), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectDecisionImpact ?? null;
  return <DetailPage basePath={basePath} backLabel="Decision impacts" backTo={backTo} description="Before-and-after policy evaluation with causal evidence." detail={detail} error={query.error} headingRef={headingRef} label="Decision impact detail" loading={query.isPending} retry={() => { void query.refetch(); }}>{detail ? <ImpactDetailCard backTo={backTo} choiceHref={`${basePath}/choices/${encodeURIComponent(detail.impact.choiceId)}`} decisionHref={`${basePath}/decisions/${encodeURIComponent(detail.impact.decisionId)}`} detail={detail} /> : null}</DetailPage>;
}

function PageHeading({ description, headingRef, title }: {
  readonly description: string;
  readonly headingRef: React.RefObject<HTMLHeadingElement>;
  readonly title: string;
}) {
  return <div><h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>{title}</h2><p className="text-body-secondary mb-0">{description}</p></div>;
}

function FilterActions({ clear }: { readonly clear: () => void }) {
  return <div className="col-12 col-sm-6 col-lg-2 d-flex gap-2"><button className="btn btn-primary" type="submit">Apply</button><button className="btn btn-outline-secondary" onClick={clear} type="button">Clear</button></div>;
}

function CollectionState({ children, connection, errorMessage, label, loading, retry }: {
  readonly children: React.ReactNode;
  readonly connection: object | null;
  readonly errorMessage: string | null;
  readonly label: string;
  readonly loading: boolean;
  readonly retry: () => void;
}) {
  if (loading && !connection) return <LoadingState label={label} />;
  if (errorMessage && !connection) return <InitialError label={label} message={errorMessage} onRetry={retry} />;
  if (!connection) return <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div>;
  return <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={retry} /> : null}{children}</>;
}

function DetailPage({ basePath, backLabel, backTo, children, description, detail, error, headingRef, label, loading, retry }: {
  readonly basePath: string;
  readonly backLabel: string;
  readonly backTo: string;
  readonly children: React.ReactNode;
  readonly description: string;
  readonly detail: object | null;
  readonly error: Error | null;
  readonly headingRef: React.RefObject<HTMLHeadingElement>;
  readonly label: string;
  readonly loading: boolean;
  readonly retry: () => void;
}) {
  const errorMessage = error instanceof Error ? error.message : null;
  return (
    <div className="vstack gap-3">
      <GovernanceNavigation basePath={basePath} />
      <div><Link className="small" to={backTo}>← Back to {backLabel}</Link><h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>{label}</h2><p className="text-body-secondary mb-0">{description}</p></div>
      {loading && !detail ? <LoadingState label={label} /> : null}
      {errorMessage && !detail ? <InitialError label={label} message={errorMessage} onRetry={retry} /> : null}
      {!loading && !errorMessage && !detail ? <div className="alert alert-info" role="status">This item is not available inside the Project.</div> : null}
      {detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={retry} /> : null}{children}</> : null}
    </div>
  );
}
