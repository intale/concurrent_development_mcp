import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type { ResourceKind, ResourceLifecycleStatus, ResourceWorkIntentionMode } from "../gql/graphql.js";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import { LatestUpdateSortControl, latestUpdateSortParams, parseLatestUpdateSort } from "../latest-update-sort.js";
import {
  fetchProjectActiveResourceWorkIntentions,
  fetchProjectResource,
  fetchProjectResourceWorkIntention,
  fetchProjectResources
} from "./project-resources-api.js";
import type { ResourceFilters, WorkIntentionFilters } from "./project-resources-api.js";
import {
  applyFilters,
  detailLocation,
  listLocation,
  nextPageParams,
  preserveCollection,
  preserveDetail,
  previousPageParams,
  RESOURCE_KINDS,
  RESOURCE_LIFECYCLE_STATUSES,
  WORK_INTENTION_MODES,
  safeReturnTo
} from "./project-resources-model.js";
import {
  AvailableStale,
  InitialError,
  WorkIntentionCards,
  WorkIntentionDetail,
  LoadingState,
  PaginationControls,
  ResourceCards,
  ResourceDetail,
  ResourceNavigation,
  useResourceHeading
} from "./project-resources-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectResourceInventoryPage() {
  const { projectRef } = useProjectWorkspace();
  const { resourceId } = useParams<{ resourceId?: string }>();

  return resourceId
    ? <ResourceDetailPage projectRef={projectRef} resourceId={resourceId} />
    : <ResourceInventoryPage projectRef={projectRef} />;
}

export function ProjectResourceWorkIntentionsPage() {
  const { projectRef } = useProjectWorkspace();
  const { intentionId } = useParams<{ intentionId?: string }>();

  return intentionId
    ? <WorkIntentionDetailPage projectRef={projectRef} intentionId={intentionId} />
    : <ActiveWorkIntentionPage projectRef={projectRef} />;
}

function ResourceInventoryPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/inventory`;
  const sectionPath = `/projects/${projectRef}/resources`;
  const path = searchParams.get("path") ?? "";
  const resourceKind = validResourceKind(searchParams.get("kind"));
  const lifecycle = validLifecycle(searchParams.get("lifecycle"));
  const after = searchParams.get("after");
  const sort = parseLatestUpdateSort(searchParams.get("sort"));
  const [draftPath, setDraftPath] = useState(path);
  const [draftKind, setDraftKind] = useState<ResourceKind | "">(resourceKind ?? "");
  const [draftLifecycle, setDraftLifecycle] = useState<ResourceLifecycleStatus | "">(lifecycle ?? "");
  const headingRef = useResourceHeading("Resource inventory", "resource-inventory");

  useEffect(() => {
    setDraftPath(path);
    setDraftKind(resourceKind ?? "");
    setDraftLifecycle(lifecycle ?? "");
  }, [path, resourceKind, lifecycle]);

  const filters: ResourceFilters = {
    sort,
    ...(path ? { path } : {}),
    ...(resourceKind ? { resourceKind } : {}),
    ...(lifecycle ? { resourceLifecycleStatus: lifecycle } : {})
  };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-resources", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchProjectResources(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      filterKey
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectResources ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  const apply = () => setSearchParams(applyFilters(searchParams, {
    path: draftPath,
    kind: draftKind,
    lifecycle: draftLifecycle
  }));

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={sectionPath} />
      <div>
        <h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Resource inventory</h2>
        <p className="text-body-secondary mb-0">Find files and directories across every Repository in this exact Project.</p>
      </div>
      <form
        aria-label="Resource filters"
        className="card card-body"
        onSubmit={(event) => { event.preventDefault(); apply(); }}
      >
        <div className="row g-3 align-items-end">
          <div className="col-12 col-lg-6">
            <label className="form-label" htmlFor="resource-path">Path contains</label>
            <input className="form-control" id="resource-path" onChange={(event) => setDraftPath(event.target.value)} value={draftPath} />
          </div>
          <div className="col-12 col-sm-6 col-lg-2">
            <label className="form-label" htmlFor="resource-kind">Kind</label>
            <select className="form-select" id="resource-kind" onChange={(event) => setDraftKind(event.target.value as ResourceKind | "")} value={draftKind}>
              <option value="">All kinds</option>
              {RESOURCE_KINDS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}
            </select>
          </div>
          <div className="col-12 col-sm-6 col-lg-2">
            <label className="form-label" htmlFor="resource-lifecycle">Lifecycle</label>
            <select className="form-select" id="resource-lifecycle" onChange={(event) => setDraftLifecycle(event.target.value as ResourceLifecycleStatus | "")} value={draftLifecycle}>
              <option value="">All states</option>
              {RESOURCE_LIFECYCLE_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}
            </select>
          </div>
          <div className="col-12 col-lg-2 d-flex gap-2">
            <button className="btn btn-primary" type="submit">Apply</button>
            <button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button>
          </div>
          <LatestUpdateSortControl id="resource-sort" onChange={(value) => setSearchParams(latestUpdateSortParams(searchParams, value))} value={sort} />
        </div>
      </form>
      {query.isPending ? <LoadingState label="Resource inventory" /> : null}
      {errorMessage && !connection ? <InitialError label="Resource inventory" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? (
        <>
          {errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
          <ResourceCards
            connection={connection}
            hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))}
          />
          <PaginationControls
            canPrevious={searchParams.getAll("trail").length > 0}
            nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null}
            onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))}
            onPrevious={() => setSearchParams(previousPageParams(searchParams))}
          />
        </>
      ) : null}
    </div>
  );
}

function ResourceDetailPage({ projectRef, resourceId }: {
  readonly projectRef: string;
  readonly resourceId: string;
}) {
  const [searchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/inventory`;
  const backTo = safeReturnTo(searchParams.get("returnTo"), listPath);
  const headingRef = useResourceHeading("Resource detail", resourceId);
  const query = useQuery({
    queryKey: ["project-resource", projectRef, resourceId],
    queryFn: ({ signal }) => fetchProjectResource(projectRef, resourceId, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      resourceId
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const resource = query.data?.projectResource ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={`/projects/${projectRef}/resources`} />
      <div>
        <Link className="btn btn-outline-secondary mb-3" to={backTo}>← Back to Resource inventory</Link>
        <h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Resource detail</h2>
        <p className="text-body-secondary mb-0">Projected identity and lifecycle evidence from ResourceGet.</p>
      </div>
      {query.isPending ? <LoadingState label="Resource detail" /> : null}
      {errorMessage && !resource ? <InitialError label="Resource detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !resource ? <div className="alert alert-info" role="status">This Resource is not available inside the Project.</div> : null}
      {resource ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<ResourceDetail backTo={backTo} resource={resource} /></> : null}
    </div>
  );
}

function ActiveWorkIntentionPage({ projectRef }: { readonly projectRef: string }) {
  const [searchParams, setSearchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/work-intentions`;
  const sectionPath = `/projects/${projectRef}/resources`;
  const current = {
    agent: searchParams.get("agent") ?? "",
    changeSet: searchParams.get("changeSet") ?? "",
    workItem: searchParams.get("workItem") ?? "",
    attempt: searchParams.get("attempt") ?? "",
    mode: searchParams.get("mode") ?? ""
  };
  const [draft, setDraft] = useState(current);
  const after = searchParams.get("after");
  const sort = parseLatestUpdateSort(searchParams.get("sort"));
  const headingRef = useResourceHeading("Active Resource work intentions", "active-resource-work-intentions");

  useEffect(() => { setDraft(current); }, [current.agent, current.changeSet, current.workItem, current.attempt, current.mode]);

  const mode = validWorkIntentionMode(current.mode);
  const filters: WorkIntentionFilters = {
    sort,
    ...(current.agent ? { agentId: current.agent } : {}),
    ...(current.changeSet ? { changeSetId: current.changeSet } : {}),
    ...(current.workItem ? { workItemId: current.workItem } : {}),
    ...(current.attempt ? { attemptId: current.attempt } : {}),
    ...(mode ? { mode } : {})
  };
  const filterKey = JSON.stringify(filters);
  const query = useQuery({
    queryKey: ["project-active-resource-work-intentions", projectRef, filterKey, after],
    queryFn: ({ signal }) => fetchProjectActiveResourceWorkIntentions(projectRef, filters, after, signal),
    placeholderData: (previousData, previousQuery) => preserveCollection(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      filterKey
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectActiveResourceWorkIntentions ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  const updateDraft = (key: keyof typeof draft, value: string) => setDraft((valueBefore) => ({ ...valueBefore, [key]: value }));

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={sectionPath} />
      <div>
        <h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Active Resource work intentions</h2>
        <p className="text-body-secondary mb-0">See who intends to change a Resource, why, and whether overlap is shared or exclusive.</p>
      </div>
      <form
        aria-label="Active work-intention filters"
        className="card card-body"
        onSubmit={(event) => { event.preventDefault(); setSearchParams(applyFilters(searchParams, draft)); }}
      >
        <div className="row g-3">
          {([
            ["agent", "Agent", "intention-agent"],
            ["changeSet", "ChangeSet", "intention-change-set"],
            ["workItem", "WorkItem", "intention-work-item"],
            ["attempt", "Attempt", "intention-attempt"]
          ] as const).map(([key, label, id]) => (
            <div className="col-12 col-md-6" key={key}>
              <label className="form-label" htmlFor={id}>{label}</label>
              <input className="form-control" id={id} onChange={(event) => updateDraft(key, event.target.value)} value={draft[key]} />
            </div>
          ))}
          <div className="col-12 col-md-6">
            <label className="form-label" htmlFor="intention-mode">Mode</label>
            <select
              className="form-select"
              id="intention-mode"
              onChange={(event) => updateDraft("mode", event.target.value)}
              value={draft.mode}
            >
              <option value="">All modes</option>
              {WORK_INTENTION_MODES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}
            </select>
          </div>
          <LatestUpdateSortControl id="work-intention-sort" onChange={(value) => setSearchParams(latestUpdateSortParams(searchParams, value))} value={sort} />
        </div>
        <div className="d-flex gap-2 mt-3">
          <button className="btn btn-primary" type="submit">Apply</button>
          <button className="btn btn-outline-secondary" onClick={() => setSearchParams({})} type="button">Clear</button>
        </div>
      </form>
      {query.isPending ? <LoadingState label="active Resource work intentions" /> : null}
      {errorMessage && !connection ? <InitialError label="Active Resource work intentions" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? (
        <>
          {errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
          <WorkIntentionCards
            connection={connection}
            hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))}
          />
          <PaginationControls
            canPrevious={searchParams.getAll("trail").length > 0}
            nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null}
            onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))}
            onPrevious={() => setSearchParams(previousPageParams(searchParams))}
          />
        </>
      ) : null}
    </div>
  );
}

function WorkIntentionDetailPage({ projectRef, intentionId }: {
  readonly projectRef: string;
  readonly intentionId: string;
}) {
  const [searchParams] = useSearchParams();
  const listPath = `/projects/${projectRef}/resources/work-intentions`;
  const backTo = safeReturnTo(searchParams.get("returnTo"), listPath);
  const headingRef = useResourceHeading("Resource work-intention detail", intentionId);
  const query = useQuery({
    queryKey: ["project-resource-work-intention", projectRef, intentionId],
    queryFn: ({ signal }) => fetchProjectResourceWorkIntention(projectRef, intentionId, signal),
    placeholderData: (previousData, previousQuery) => preserveDetail(
      previousData,
      previousQuery?.queryKey,
      projectRef,
      intentionId
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const intention = query.data?.projectResourceWorkIntention ?? null;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  return (
    <div className="vstack gap-3">
      <ResourceNavigation basePath={`/projects/${projectRef}/resources`} />
      <div>
        <Link className="btn btn-outline-secondary mb-3" to={backTo}>← Back to active work intentions</Link>
        <h2 className="h3 mt-2 mb-1" ref={headingRef} tabIndex={-1}>Resource work-intention detail</h2>
        <p className="text-body-secondary mb-0">Historical intention facts remain available after withdrawal, expiry, or Attempt completion.</p>
      </div>
      {query.isPending ? <LoadingState label="Resource work-intention detail" /> : null}
      {errorMessage && !intention ? <InitialError label="Resource work-intention detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !intention ? <div className="alert alert-info" role="status">This work intention is not available inside the Project.</div> : null}
      {intention ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<WorkIntentionDetail backTo={backTo} intention={intention} projectPath={`/projects/${projectRef}`} /></> : null}
    </div>
  );
}

function validResourceKind(value: string | null): ResourceKind | undefined {
  return RESOURCE_KINDS.some((item) => item.value === value) ? value as ResourceKind : undefined;
}

function validLifecycle(value: string | null): ResourceLifecycleStatus | undefined {
  return RESOURCE_LIFECYCLE_STATUSES.some((item) => item.value === value)
    ? value as ResourceLifecycleStatus
    : undefined;
}

function validWorkIntentionMode(value: string | null): ResourceWorkIntentionMode | undefined {
  return WORK_INTENTION_MODES.some((item) => item.value === value)
    ? value as ResourceWorkIntentionMode
    : undefined;
}
