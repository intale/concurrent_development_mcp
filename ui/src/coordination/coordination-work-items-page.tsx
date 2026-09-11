import { useMemo } from "react";
import type { FormEvent } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type { CoordinationPresentationStatus, WorkItemSort } from "../gql/graphql.js";
import { useProjectWorkspace } from "../projects/project-workspace-shell.js";
import { fetchProjectWorkItem, fetchProjectWorkItems } from "./project-coordination-api.js";
import {
  detailLocation,
  exactWorkItemFilterParams,
  listLocation,
  nextPageParams,
  PRESENTATION_STATUSES,
  previousPageParams,
  resetPagination,
  safeReturnTo,
  WORK_ITEM_SORTS
} from "./project-coordination-model.js";
import {
  AvailableStale,
  CoordinationNavigation,
  InitialError,
  LoadingState,
  PaginationControls,
  useCoordinationHeading,
  WorkItemCards,
  WorkItemDetail
} from "./project-coordination-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function CoordinationWorkItemsPage() {
  const { workItemId } = useParams<{ workItemId?: string }>();
  return workItemId ? <WorkItemDetailPage workItemId={workItemId} /> : <WorkItemListPage />;
}

function WorkItemListPage() {
  const { project, projectRef } = useProjectWorkspace();
  const [searchParams, setSearchParams] = useSearchParams();
  const statuses = useMemo(() => searchParams.getAll("status").filter(
    (status): status is CoordinationPresentationStatus => PRESENTATION_STATUSES.includes(status as CoordinationPresentationStatus)
  ), [searchParams]);
  const requestedSort = searchParams.get("sort") as WorkItemSort | null;
  const sort = WORK_ITEM_SORTS.some(({ value }) => value === requestedSort) ? requestedSort as WorkItemSort : "UPDATED_AT_DESC";
  const changeSetId = searchParams.get("changeSet")?.trim() || undefined;
  const agentId = searchParams.get("agent")?.trim() || undefined;
  const after = searchParams.get("after") ?? undefined;
  const basePath = `/projects/${projectRef}/coordination`;
  const listPath = `${basePath}/work-items`;
  const headingRef = useCoordinationHeading(`WorkItems · ${project.displayLabel}`, after ?? "first");
  const filters = { presentationStatuses: statuses, sort, ...(changeSetId ? { changeSetId } : {}), ...(agentId ? { agentId } : {}) };
  const query = useQuery({
    queryKey: ["project-work-items", projectRef, filters, after],
    queryFn: ({ signal }) => fetchProjectWorkItems(projectRef, filters, after, signal),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const connection = query.data?.projectWorkItems;
  const errorMessage = query.error instanceof Error ? query.error.message : null;

  const updateFilter = (key: string, value: string | null) => {
    const next = resetPagination(searchParams);
    if (value) next.set(key, value);
    else next.delete(key);
    setSearchParams(next);
  };
  const toggleStatus = (status: CoordinationPresentationStatus) => {
    const next = resetPagination(searchParams);
    next.delete("status");
    const selected = statuses.includes(status) ? statuses.filter((item) => item !== status) : [...statuses, status];
    selected.forEach((item) => next.append("status", item));
    setSearchParams(next);
  };
  const applyExactFilters = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setSearchParams(exactWorkItemFilterParams(
      searchParams,
      form.get("changeSet")?.toString() ?? "",
      form.get("agent")?.toString() ?? ""
    ));
  };

  return (
    <div className="vstack gap-3">
      <CoordinationNavigation basePath={basePath} />
      <div><h2 className="h3 mb-1" ref={headingRef} tabIndex={-1}>Scheduled WorkItems</h2><p className="text-body-secondary mb-0">See what is pending, assigned, running, or completed—and who currently owns the work.</p></div>
      <form
        aria-label="WorkItem filters"
        className="card card-body"
        key={`${changeSetId ?? ""}:${agentId ?? ""}`}
        onSubmit={applyExactFilters}
      >
        <div className="row g-3">
          <fieldset className="col-12"><legend className="form-label fs-6">Status</legend><div className="d-flex flex-wrap gap-3">{PRESENTATION_STATUSES.map((status) => <label className="form-check" key={status}><input checked={statuses.includes(status)} className="form-check-input" onChange={() => toggleStatus(status)} type="checkbox" /><span className="form-check-label">{status.toLowerCase()}</span></label>)}</div></fieldset>
          <div className="col-12 col-md-4"><label className="form-label" htmlFor="work-item-sort">Sort</label><select className="form-select" id="work-item-sort" onChange={(event) => updateFilter("sort", event.target.value)} value={sort}>{WORK_ITEM_SORTS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
          <div className="col-12 col-md-4"><label className="form-label" htmlFor="work-item-change-set">ChangeSet ID</label><input className="form-control" defaultValue={changeSetId} id="work-item-change-set" name="changeSet" placeholder="Optional exact ID" /></div>
          <div className="col-12 col-md-4"><label className="form-label" htmlFor="work-item-agent">Agent</label><input className="form-control" defaultValue={agentId} id="work-item-agent" name="agent" placeholder="Optional exact agent" /></div>
          <div className="col-12"><button className="btn btn-outline-primary" type="submit">Apply exact filters</button></div>
        </div>
      </form>
      {query.isPending ? <LoadingState label="WorkItems" /> : null}
      {errorMessage && !connection ? <InitialError label="WorkItems" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}
      {!query.isPending && !errorMessage && !connection ? <div className="alert alert-warning" role="status">This Project is not available in the latest projection.</div> : null}
      {connection ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<WorkItemCards hrefFor={(id) => detailLocation(listPath, id, listLocation(listPath, searchParams))} items={connection.nodes} /><PaginationControls canPrevious={searchParams.getAll("trail").length > 0} nextCursor={connection.pageInfo.hasNextPage ? connection.pageInfo.endCursor : null} onNext={(cursor) => setSearchParams(nextPageParams(searchParams, cursor))} onPrevious={() => setSearchParams(previousPageParams(searchParams))} /></> : null}
    </div>
  );
}

function WorkItemDetailPage({ workItemId }: { readonly workItemId: string }) {
  const { project, projectRef } = useProjectWorkspace();
  const [searchParams] = useSearchParams();
  const basePath = `/projects/${projectRef}/coordination`;
  const listPath = `${basePath}/work-items`;
  const backTo = safeReturnTo(searchParams.get("returnTo"), listPath);
  const headingRef = useCoordinationHeading(`WorkItem · ${project.displayLabel}`, workItemId);
  const query = useQuery({ queryKey: ["project-work-item", projectRef, workItemId], queryFn: ({ signal }) => fetchProjectWorkItem(projectRef, workItemId, signal), refetchInterval: REFRESH_INTERVAL_MS });
  const detail = query.data?.projectWorkItem;
  const errorMessage = query.error instanceof Error ? query.error.message : null;
  return <div className="vstack gap-3"><CoordinationNavigation basePath={basePath} /><div><Link className="btn btn-outline-secondary mb-3" to={backTo}>← Back to WorkItems</Link><h2 className="h3 mb-0" ref={headingRef} tabIndex={-1}>WorkItem detail</h2></div>{query.isPending ? <LoadingState label="WorkItem detail" /> : null}{errorMessage && !detail ? <InitialError label="WorkItem detail" message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}{!query.isPending && !errorMessage && !detail ? <div className="alert alert-info" role="status">This WorkItem is not available in this Project.</div> : null}{detail ? <>{errorMessage ? <AvailableStale message={errorMessage} onRetry={() => { void query.refetch(); }} /> : null}<WorkItemDetail detail={detail} /></> : null}</div>;
}
