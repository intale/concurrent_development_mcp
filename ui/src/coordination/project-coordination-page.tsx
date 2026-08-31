import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type { CoordinationPresentationStatus, WorkItemSort } from "../gql/graphql.js";
import { fetchProjectCoordination } from "./project-coordination-api.js";
import type { CoordinationCursors } from "./project-coordination-api.js";
import {
  PRESENTATION_STATUSES,
  WORK_ITEM_SORTS,
  preserveDashboardForProject
} from "./project-coordination-model.js";
import { ProjectCoordinationView } from "./project-coordination-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectCoordinationPage() {
  const { repositoryId = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const statuses = useMemo(() => {
    const requested = searchParams.getAll("status") as CoordinationPresentationStatus[];
    return requested.filter((status) => PRESENTATION_STATUSES.includes(status));
  }, [searchParams]);
  const requestedSort = searchParams.get("sort") as WorkItemSort | null;
  const workItemSort = WORK_ITEM_SORTS.some(({ value }) => value === requestedSort)
    ? requestedSort as WorkItemSort
    : "WORK_ITEM_ID_ASC";
  const blocking = searchParams.get("blocking") === "true" ? true : undefined;
  const [cursors, setCursors] = useState<CoordinationCursors>({});

  useEffect(() => {
    setCursors({});
  }, [repositoryId, searchParams]);

  const filters = { presentationStatuses: statuses, workItemSort, ...(blocking ? { blocking } : {}) };
  const dashboard = useQuery({
    queryKey: ["project-coordination", repositoryId, filters, cursors],
    queryFn: ({ signal }) => fetchProjectCoordination(repositoryId, filters, cursors, signal),
    enabled: repositoryId.length > 0,
    placeholderData: (previousData, previousQuery) => (
      preserveDashboardForProject(previousData, previousQuery?.queryKey, repositoryId)
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const toggleStatus = (status: CoordinationPresentationStatus) => {
    const next = new URLSearchParams(searchParams);
    next.delete("status");
    const selected = statuses.includes(status) ? statuses.filter((item) => item !== status) : [...statuses, status];
    selected.forEach((item) => next.append("status", item));
    setSearchParams(next);
  };

  const errorMessage = dashboard.error instanceof Error ? dashboard.error.message : null;

  return (
    <>
      <div className="app-content-header"><div className="container-fluid"><div className="row align-items-center">
        <div className="col-sm-6"><h1 className="mb-0">Project coordination</h1></div>
        <div className="col-sm-6"><ol className="breadcrumb float-sm-end mb-0"><li className="breadcrumb-item"><Link to="/projects">Projects</Link></li><li aria-current="page" className="breadcrumb-item active">Coordination</li></ol></div>
      </div></div></div>
      <div className="app-content"><div className="container-fluid vstack gap-4">
        <form aria-label="Coordination filters" className="card card-body" onSubmit={(event) => event.preventDefault()}>
          <div className="row g-3 align-items-end">
            <fieldset className="col-12 col-lg"><legend className="form-label fs-6">Presentation status</legend><div className="d-flex flex-wrap gap-2">
              {PRESENTATION_STATUSES.map((status) => <label className="form-check form-check-inline" key={status}><input checked={statuses.includes(status)} className="form-check-input" onChange={() => toggleStatus(status)} type="checkbox" /><span className="form-check-label">{status.toLowerCase()}</span></label>)}
            </div></fieldset>
            <div className="col-12 col-md-4"><label className="form-label" htmlFor="work-item-sort">Sort work items</label><select className="form-select" id="work-item-sort" onChange={(event) => { const next = new URLSearchParams(searchParams); next.set("sort", event.target.value); setSearchParams(next); }} value={workItemSort}>{WORK_ITEM_SORTS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-md-auto"><div className="form-check form-switch mb-2"><input checked={blocking === true} className="form-check-input" id="blocking-only" onChange={(event) => { const next = new URLSearchParams(searchParams); if (event.target.checked) next.set("blocking", "true"); else next.delete("blocking"); setSearchParams(next); }} type="checkbox" /><label className="form-check-label" htmlFor="blocking-only">Blocking dependencies only</label></div></div>
          </div>
        </form>
        <ProjectCoordinationView
          dashboard={dashboard.data?.projectCoordination ?? null}
          errorMessage={errorMessage}
          loading={dashboard.isPending}
          onNextChangeSets={(cursor) => setCursors((current) => ({ ...current, changeSetsAfter: cursor }))}
          onNextDependencies={(cursor) => setCursors((current) => ({ ...current, dependenciesAfter: cursor }))}
          onNextWorkItems={(cursor) => setCursors((current) => ({ ...current, workItemsAfter: cursor }))}
          onRetry={() => { void dashboard.refetch(); }}
          refreshing={dashboard.isFetching && dashboard.data !== undefined}
        />
      </div></div>
    </>
  );
}
