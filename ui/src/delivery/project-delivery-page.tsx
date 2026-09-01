import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type {
  CandidateCheckpointKind,
  DeliverySort,
  OperationBatchStatus,
  OperationBatchTool,
  ReleaseSetStatus,
  VerificationObligationStatus
} from "../gql/graphql.js";
import {
  fetchBatch,
  fetchBatches,
  fetchCandidate,
  fetchMerge,
  fetchProjectDelivery,
  fetchRelease,
  fetchVerification
} from "./project-delivery-api.js";
import {
  BATCH_STATUSES,
  BATCH_TOOLS,
  CHECKPOINT_KINDS,
  DELIVERY_SORTS,
  impactDirection,
  OBLIGATION_STATUSES,
  preserveForIdentity,
  preserveForProject,
  preserveGlobalIdentity,
  RELEASE_STATUSES
} from "./project-delivery-model.js";
import { ProjectDeliveryView } from "./project-delivery-view.js";

const REFRESH_INTERVAL_MS = 15_000;

function matching<T extends string>(
  requested: string | null,
  options: ReadonlyArray<{ readonly value: T }>
): T | undefined {
  return options.some(({ value }) => value === requested) ? requested as T : undefined;
}

export function ProjectDeliveryPage() {
  const { repositoryId = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const sort = matching<DeliverySort>(searchParams.get("sort"), DELIVERY_SORTS) ?? "NEWEST_FIRST";
  const candidateCheckpointKind = matching<CandidateCheckpointKind>(searchParams.get("checkpointKind"), CHECKPOINT_KINDS);
  const obligationStatus = matching<VerificationObligationStatus>(searchParams.get("obligationStatus"), OBLIGATION_STATUSES);
  const releaseStatus = matching<ReleaseSetStatus>(searchParams.get("releaseStatus"), RELEASE_STATUSES);
  const batchStatus = matching<OperationBatchStatus>(searchParams.get("batchStatus"), BATCH_STATUSES);
  const batchTool = matching<OperationBatchTool>(searchParams.get("batchTool"), BATCH_TOOLS);
  const candidateChangeSetId = searchParams.get("candidateChangeSet")?.trim() || undefined;
  const obligationChangeSetId = searchParams.get("obligationChangeSet")?.trim() || undefined;
  const releaseChangeSetId = searchParams.get("releaseChangeSet")?.trim() || undefined;
  const selectedCandidate = searchParams.get("candidate") ?? undefined;
  const selectedObligation = searchParams.get("obligation") ?? undefined;
  const selectedMerge = searchParams.get("merge") ?? undefined;
  const selectedRelease = searchParams.get("release") ?? undefined;
  const selectedBatch = searchParams.get("batch") ?? undefined;
  const direction = impactDirection(searchParams.get("impactDirection"));

  const deliveryFilters = {
    sort,
    ...(candidateChangeSetId ? { candidateChangeSetId } : {}),
    ...(candidateCheckpointKind ? { candidateCheckpointKind } : {}),
    ...(obligationChangeSetId ? { obligationChangeSetId } : {}),
    ...(obligationStatus ? { obligationStatus } : {}),
    ...(releaseChangeSetId ? { releaseChangeSetId } : {}),
    ...(releaseStatus ? { releaseStatus } : {})
  };
  const deliveryCursors = {
    ...(searchParams.get("candidatesAfter") ? { afterCandidate: searchParams.get("candidatesAfter") as string } : {}),
    ...(searchParams.get("obligationsAfter") ? { afterObligation: searchParams.get("obligationsAfter") as string } : {}),
    ...(searchParams.get("mergesAfter") ? { afterMergeSnapshot: searchParams.get("mergesAfter") as string } : {}),
    ...(searchParams.get("releasesAfter") ? { afterReleaseSet: searchParams.get("releasesAfter") as string } : {})
  };
  const batchFilters = {
    sort,
    ...(batchStatus ? { status: batchStatus } : {}),
    ...(batchTool ? { targetTool: batchTool } : {})
  };

  const catalog = useQuery({
    queryKey: ["project-delivery", repositoryId, deliveryFilters, deliveryCursors],
    queryFn: ({ signal }) => fetchProjectDelivery(repositoryId, deliveryFilters, deliveryCursors, signal),
    enabled: repositoryId.length > 0,
    placeholderData: (previousData, previousQuery) => preserveForProject(
      previousData,
      previousQuery?.queryKey,
      repositoryId
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const candidate = useQuery({
    queryKey: ["delivery-candidate", repositoryId, selectedCandidate, direction, searchParams.get("impactsAfter")],
    queryFn: ({ signal }) => fetchCandidate(
      repositoryId,
      selectedCandidate ?? "",
      direction,
      searchParams.get("impactsAfter") ?? undefined,
      signal
    ),
    enabled: repositoryId.length > 0 && selectedCandidate !== undefined,
    placeholderData: (previousData, previousQuery) => preserveForIdentity(
      previousData,
      previousQuery?.queryKey,
      repositoryId,
      selectedCandidate ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const verification = useQuery({
    queryKey: ["delivery-verification", repositoryId, selectedObligation, searchParams.get("evidenceAfter")],
    queryFn: ({ signal }) => fetchVerification(
      repositoryId,
      selectedObligation ?? "",
      searchParams.get("evidenceAfter") ?? undefined,
      signal
    ),
    enabled: repositoryId.length > 0 && selectedObligation !== undefined,
    placeholderData: (previousData, previousQuery) => preserveForIdentity(
      previousData,
      previousQuery?.queryKey,
      repositoryId,
      selectedObligation ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const merge = useQuery({
    queryKey: ["delivery-merge", repositoryId, selectedMerge, searchParams.get("authorizationsAfter")],
    queryFn: ({ signal }) => fetchMerge(
      repositoryId,
      selectedMerge ?? "",
      searchParams.get("authorizationsAfter") ?? undefined,
      signal
    ),
    enabled: repositoryId.length > 0 && selectedMerge !== undefined,
    placeholderData: (previousData, previousQuery) => preserveForIdentity(
      previousData,
      previousQuery?.queryKey,
      repositoryId,
      selectedMerge ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const release = useQuery({
    queryKey: ["delivery-release", repositoryId, selectedRelease],
    queryFn: ({ signal }) => fetchRelease(repositoryId, selectedRelease ?? "", signal),
    enabled: repositoryId.length > 0 && selectedRelease !== undefined,
    placeholderData: (previousData, previousQuery) => preserveForIdentity(
      previousData,
      previousQuery?.queryKey,
      repositoryId,
      selectedRelease ?? ""
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const batches = useQuery({
    queryKey: ["delivery-batches", batchFilters, searchParams.get("batchesAfter")],
    queryFn: ({ signal }) => fetchBatches(
      batchFilters,
      searchParams.get("batchesAfter") ?? undefined,
      signal
    ),
    placeholderData: (previousData) => previousData,
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const batch = useQuery({
    queryKey: ["delivery-batch", selectedBatch, searchParams.get("batchItemsAfter")],
    queryFn: ({ signal }) => fetchBatch(
      selectedBatch ?? "",
      searchParams.get("batchItemsAfter") ?? undefined,
      signal
    ),
    enabled: selectedBatch !== undefined,
    placeholderData: (previousData, previousQuery) => preserveGlobalIdentity(
      previousData,
      previousQuery?.queryKey,
      selectedBatch ?? ""
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
    return `/projects/${repositoryId}/delivery?${next.toString()}`;
  };
  const queries = [catalog, candidate, verification, merge, release, batches, batch];
  const errors = queries.map((query) => query.error).filter((error): error is Error => error instanceof Error);
  const retry = () => {
    void catalog.refetch();
    void batches.refetch();
    if (selectedCandidate) void candidate.refetch();
    if (selectedObligation) void verification.refetch();
    if (selectedMerge) void merge.refetch();
    if (selectedRelease) void release.refetch();
    if (selectedBatch) void batch.refetch();
  };

  return (
    <>
      <div className="app-content-header"><div className="container-fluid"><div className="row align-items-center"><div className="col-sm-6"><h1 className="mb-0">Project delivery</h1></div><div className="col-sm-6"><ol className="breadcrumb float-sm-end mb-0"><li className="breadcrumb-item"><Link to="/projects">Projects</Link></li><li aria-current="page" className="breadcrumb-item active">Delivery</li></ol></div></div></div></div>
      <div className="app-content"><div className="container-fluid vstack gap-4">
        <form aria-label="Delivery filters" className="card card-body" onSubmit={(event) => event.preventDefault()}>
          <div className="row g-3">
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="delivery-sort">Timeline order</label><select className="form-select" id="delivery-sort" onChange={(event) => update({ sort: event.target.value, candidatesAfter: null, obligationsAfter: null, mergesAfter: null, releasesAfter: null, batchesAfter: null })} value={sort}>{DELIVERY_SORTS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="candidate-change-set">Candidate ChangeSet</label><input className="form-control" id="candidate-change-set" onChange={(event) => update({ candidateChangeSet: event.target.value, candidatesAfter: null })} placeholder="Exact ChangeSet ID" value={searchParams.get("candidateChangeSet") ?? ""} /></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="checkpoint-kind">Checkpoint kind</label><select className="form-select" id="checkpoint-kind" onChange={(event) => update({ checkpointKind: event.target.value, candidatesAfter: null })} value={candidateCheckpointKind ?? ""}><option value="">All kinds</option>{CHECKPOINT_KINDS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="obligation-status">Obligation status</label><select className="form-select" id="obligation-status" onChange={(event) => update({ obligationStatus: event.target.value, obligationsAfter: null })} value={obligationStatus ?? ""}><option value="">All statuses</option>{OBLIGATION_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="release-status">ReleaseSet status</label><select className="form-select" id="release-status" onChange={(event) => update({ releaseStatus: event.target.value, releasesAfter: null })} value={releaseStatus ?? ""}><option value="">All statuses</option>{RELEASE_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="batch-status">Global batch status</label><select className="form-select" id="batch-status" onChange={(event) => update({ batchStatus: event.target.value, batchesAfter: null })} value={batchStatus ?? ""}><option value="">All statuses</option>{BATCH_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="batch-tool">Global batch tool</label><select className="form-select" id="batch-tool" onChange={(event) => update({ batchTool: event.target.value, batchesAfter: null })} value={batchTool ?? ""}><option value="">All tools</option>{BATCH_TOOLS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
          </div>
        </form>
        <ProjectDeliveryView
          batch={batch.data?.operationBatch ?? null}
          batches={batches.data?.operationBatches ?? null}
          browser={catalog.data?.projectDelivery ?? null}
          candidate={candidate.data?.projectCandidateCheckpoint ?? null}
          errorMessage={errors.map((error) => error.message).join("; ") || null}
          hrefForBatch={(id) => href({ batch: id, candidate: null, obligation: null, merge: null, release: null, batchItemsAfter: null })}
          hrefForCandidate={(id) => href({ candidate: id, obligation: null, merge: null, release: null, batch: null, impactsAfter: null })}
          hrefForMerge={(id) => href({ merge: id, candidate: null, obligation: null, release: null, batch: null, authorizationsAfter: null })}
          hrefForObligation={(id) => href({ obligation: id, candidate: null, merge: null, release: null, batch: null, evidenceAfter: null })}
          hrefForRelease={(id) => href({ release: id, candidate: null, obligation: null, merge: null, batch: null })}
          loading={catalog.isPending}
          merge={merge.data?.projectMergeSnapshot ?? null}
          onNextAuthorizations={(cursor) => update({ authorizationsAfter: cursor })}
          onNextBatchItems={(cursor) => update({ batchItemsAfter: cursor })}
          onNextBatches={(cursor) => update({ batchesAfter: cursor })}
          onNextCandidates={(cursor) => update({ candidatesAfter: cursor })}
          onNextEvidence={(cursor) => update({ evidenceAfter: cursor })}
          onNextImpacts={(cursor) => update({ impactsAfter: cursor })}
          onNextMerges={(cursor) => update({ mergesAfter: cursor })}
          onNextObligations={(cursor) => update({ obligationsAfter: cursor })}
          onNextReleases={(cursor) => update({ releasesAfter: cursor })}
          onRetry={retry}
          refreshing={queries.some((query) => query.isFetching && query.data !== undefined)}
          release={release.data?.projectReleaseSet ?? null}
          verification={verification.data?.projectVerificationObligation ?? null}
        />
      </div></div>
    </>
  );
}
