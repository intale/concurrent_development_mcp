import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type {
  AgentChoiceImpactOutcome,
  AgentChoiceKind,
  AgentChoiceStatus,
  DecisionPolicyStatus,
  GuidanceSource
} from "../gql/graphql.js";
import {
  fetchGovernanceAgentChoice,
  fetchGovernanceDecision,
  fetchGovernanceGuidance,
  fetchProjectGovernance
} from "./project-governance-api.js";
import {
  AGENT_CHOICE_KINDS,
  AGENT_CHOICE_STATUSES,
  DECISION_POLICY_STATUSES,
  GUIDANCE_SOURCES,
  IMPACT_OUTCOMES,
  preserveDetailForIdentity,
  preserveGovernanceForProject
} from "./project-governance-model.js";
import { ProjectGovernanceView } from "./project-governance-view.js";

const REFRESH_INTERVAL_MS = 15_000;

function matching<T extends string>(
  requested: string | null,
  options: ReadonlyArray<{ readonly value: T }>
): T | undefined {
  return options.some(({ value }) => value === requested) ? requested as T : undefined;
}

export function ProjectGovernancePage() {
  const { repositoryId = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const decisionPolicyStatus = matching<DecisionPolicyStatus>(searchParams.get("decisionStatus"), DECISION_POLICY_STATUSES);
  const guidanceSource = matching<GuidanceSource>(searchParams.get("guidanceSource"), GUIDANCE_SOURCES);
  const choiceType = matching<AgentChoiceKind>(searchParams.get("choiceType"), AGENT_CHOICE_KINDS);
  const choiceStatus = matching<AgentChoiceStatus>(searchParams.get("choiceStatus"), AGENT_CHOICE_STATUSES);
  const impactOutcome = matching<AgentChoiceImpactOutcome>(searchParams.get("impactOutcome"), IMPACT_OUTCOMES);
  const decisionTopicId = searchParams.get("decisionTopic")?.trim() || undefined;
  const selectedDecision = searchParams.get("decision") ?? undefined;
  const selectedGuidance = searchParams.get("guidance") ?? undefined;
  const selectedChoice = searchParams.get("choice") ?? undefined;

  const filters = {
    ...(decisionPolicyStatus ? { decisionPolicyStatus } : {}),
    ...(decisionTopicId ? { decisionTopicId } : {}),
    ...(guidanceSource ? { guidanceSource } : {}),
    ...(choiceType ? { choiceType } : {}),
    ...(choiceStatus ? { choiceStatus } : {}),
    ...(impactOutcome ? { impactOutcome } : {})
  };
  const cursors = {
    ...(searchParams.get("decisionsAfter") ? { afterDecision: searchParams.get("decisionsAfter") as string } : {}),
    ...(searchParams.get("guidanceAfter") ? { afterGuidance: searchParams.get("guidanceAfter") as string } : {}),
    ...(searchParams.get("choicesAfter") ? { afterChoice: searchParams.get("choicesAfter") as string } : {}),
    ...(searchParams.get("impactsAfter") ? { afterImpact: searchParams.get("impactsAfter") as string } : {})
  };

  const catalog = useQuery({
    queryKey: ["project-governance", repositoryId, filters, cursors],
    queryFn: ({ signal }) => fetchProjectGovernance(repositoryId, filters, cursors, signal),
    enabled: repositoryId.length > 0,
    placeholderData: (previousData, previousQuery) => (
      preserveGovernanceForProject(previousData, previousQuery?.queryKey, repositoryId)
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const decision = useQuery({
    queryKey: ["governance-decision", repositoryId, selectedDecision],
    queryFn: ({ signal }) => fetchGovernanceDecision(repositoryId, selectedDecision ?? "", signal),
    enabled: repositoryId.length > 0 && selectedDecision !== undefined,
    placeholderData: (previousData, previousQuery) => preserveDetailForIdentity(
      previousData,
      previousQuery?.queryKey,
      repositoryId,
      selectedDecision ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const guidance = useQuery({
    queryKey: ["governance-guidance", repositoryId, selectedGuidance, searchParams.get("interpretationsAfter")],
    queryFn: ({ signal }) => fetchGovernanceGuidance(
      repositoryId,
      selectedGuidance ?? "",
      searchParams.get("interpretationsAfter") ?? undefined,
      signal
    ),
    enabled: repositoryId.length > 0 && selectedGuidance !== undefined,
    placeholderData: (previousData, previousQuery) => preserveDetailForIdentity(
      previousData,
      previousQuery?.queryKey,
      repositoryId,
      selectedGuidance ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const choice = useQuery({
    queryKey: ["governance-choice", repositoryId, selectedChoice, searchParams.get("choiceImpactsAfter")],
    queryFn: ({ signal }) => fetchGovernanceAgentChoice(
      repositoryId,
      selectedChoice ?? "",
      searchParams.get("choiceImpactsAfter") ?? undefined,
      signal
    ),
    enabled: repositoryId.length > 0 && selectedChoice !== undefined,
    placeholderData: (previousData, previousQuery) => preserveDetailForIdentity(
      previousData,
      previousQuery?.queryKey,
      repositoryId,
      selectedChoice ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const update = (changes: Readonly<Record<string, string | null>>) => {
    const next = new URLSearchParams(searchParams);
    Object.entries(changes).forEach(([name, value]) => value ? next.set(name, value) : next.delete(name));
    setSearchParams(next);
  };
  const href = (changes: Readonly<Record<string, string | null>>) => {
    const next = new URLSearchParams(searchParams);
    Object.entries(changes).forEach(([name, value]) => value ? next.set(name, value) : next.delete(name));
    return `/projects/${repositoryId}/governance?${next.toString()}`;
  };
  const queries = [catalog, decision, guidance, choice];
  const errors = queries.map((query) => query.error).filter((error): error is Error => error instanceof Error);
  const retry = () => {
    void catalog.refetch();
    if (selectedDecision) void decision.refetch();
    if (selectedGuidance) void guidance.refetch();
    if (selectedChoice) void choice.refetch();
  };

  return (
    <>
      <div className="app-content-header"><div className="container-fluid"><div className="row align-items-center"><div className="col-sm-6"><h1 className="mb-0">Project governance</h1></div><div className="col-sm-6"><ol className="breadcrumb float-sm-end mb-0"><li className="breadcrumb-item"><Link to="/projects">Projects</Link></li><li aria-current="page" className="breadcrumb-item active">Governance</li></ol></div></div></div></div>
      <div className="app-content"><div className="container-fluid vstack gap-4">
        <form aria-label="Governance filters" className="card card-body" onSubmit={(event) => event.preventDefault()}>
          <div className="row g-3">
            <div className="col-12 col-lg-4"><label className="form-label" htmlFor="decision-topic">Decision topic</label><input className="form-control" id="decision-topic" onChange={(event) => update({ decisionTopic: event.target.value, decisionsAfter: null })} placeholder="Exact topic ID" value={searchParams.get("decisionTopic") ?? ""} /></div>
            <div className="col-12 col-lg-4"><label className="form-label" htmlFor="decision-status">Decision status</label><select className="form-select" id="decision-status" onChange={(event) => update({ decisionStatus: event.target.value, decisionsAfter: null })} value={decisionPolicyStatus ?? ""}><option value="">All statuses</option>{DECISION_POLICY_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-4"><label className="form-label" htmlFor="guidance-source">Guidance source</label><select className="form-select" id="guidance-source" onChange={(event) => update({ guidanceSource: event.target.value, guidanceAfter: null })} value={guidanceSource ?? ""}><option value="">All sources</option>{GUIDANCE_SOURCES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-4"><label className="form-label" htmlFor="choice-type">AgentChoice kind</label><select className="form-select" id="choice-type" onChange={(event) => update({ choiceType: event.target.value, choicesAfter: null })} value={choiceType ?? ""}><option value="">All kinds</option>{AGENT_CHOICE_KINDS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-4"><label className="form-label" htmlFor="choice-status">AgentChoice status</label><select className="form-select" id="choice-status" onChange={(event) => update({ choiceStatus: event.target.value, choicesAfter: null })} value={choiceStatus ?? ""}><option value="">All statuses</option>{AGENT_CHOICE_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-4"><label className="form-label" htmlFor="impact-outcome">Impact outcome</label><select className="form-select" id="impact-outcome" onChange={(event) => update({ impactOutcome: event.target.value, impactsAfter: null })} value={impactOutcome ?? ""}><option value="">All outcomes</option>{IMPACT_OUTCOMES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
          </div>
        </form>
        <ProjectGovernanceView
          browser={catalog.data?.projectGovernance ?? null}
          choice={choice.data?.projectAgentChoice ?? null}
          decision={decision.data?.projectDecision ?? null}
          errorMessage={errors.map((error) => error.message).join("; ") || null}
          guidance={guidance.data?.projectGuidance ?? null}
          hrefForChoice={(choiceId) => href({ choice: choiceId, decision: null, guidance: null, choiceImpactsAfter: null })}
          hrefForDecision={(decisionId) => href({ decision: decisionId, guidance: null, choice: null })}
          hrefForGuidance={(messageId) => href({ guidance: messageId, decision: null, choice: null, interpretationsAfter: null })}
          loading={catalog.isPending}
          onNextChoices={(cursor) => update({ choicesAfter: cursor })}
          onNextDecisions={(cursor) => update({ decisionsAfter: cursor })}
          onNextGuidance={(cursor) => update({ guidanceAfter: cursor })}
          onNextImpacts={(cursor) => update({ impactsAfter: cursor })}
          onNextInterpretations={(cursor) => update({ interpretationsAfter: cursor })}
          onNextSelectedChoiceImpacts={(cursor) => update({ choiceImpactsAfter: cursor })}
          onRetry={retry}
          refreshing={queries.some((query) => query.isFetching && query.data !== undefined)}
        />
      </div></div>
    </>
  );
}
