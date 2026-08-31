import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type { ResourceKind, ResourceLifecycleStatus } from "../gql/graphql.js";
import { fetchProjectResources } from "./project-resources-api.js";
import type { ResourceCursors } from "./project-resources-api.js";
import {
  RESOURCE_KINDS,
  RESOURCE_LIFECYCLE_STATUSES,
  preserveResourcesForProject
} from "./project-resources-model.js";
import { ProjectResourcesView } from "./project-resources-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectResourcesPage() {
  const { repositoryId = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const requestedKind = searchParams.get("kind") as ResourceKind | null;
  const resourceKind = RESOURCE_KINDS.some(({ value }) => value === requestedKind)
    ? requestedKind as ResourceKind
    : undefined;
  const requestedLifecycle = searchParams.get("lifecycle") as ResourceLifecycleStatus | null;
  const resourceLifecycleStatus = RESOURCE_LIFECYCLE_STATUSES.some(({ value }) => value === requestedLifecycle)
    ? requestedLifecycle as ResourceLifecycleStatus
    : undefined;
  const [cursors, setCursors] = useState<ResourceCursors>({});

  useEffect(() => {
    setCursors({});
  }, [repositoryId, resourceKind, resourceLifecycleStatus]);

  const filters = {
    ...(resourceKind ? { resourceKind } : {}),
    ...(resourceLifecycleStatus ? { resourceLifecycleStatus } : {})
  };
  const resources = useQuery({
    queryKey: ["project-resources", repositoryId, filters, cursors],
    queryFn: ({ signal }) => fetchProjectResources(repositoryId, filters, cursors, signal),
    enabled: repositoryId.length > 0,
    placeholderData: (previousData, previousQuery) => (
      preserveResourcesForProject(previousData, previousQuery?.queryKey, repositoryId)
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const setFilter = (name: "kind" | "lifecycle", value: string) => {
    const next = new URLSearchParams(searchParams);
    if (value) next.set(name, value);
    else next.delete(name);
    setSearchParams(next);
  };
  const errorMessage = resources.error instanceof Error ? resources.error.message : null;

  return (
    <>
      <div className="app-content-header"><div className="container-fluid"><div className="row align-items-center">
        <div className="col-sm-6"><h1 className="mb-0">Project resources</h1></div>
        <div className="col-sm-6"><ol className="breadcrumb float-sm-end mb-0"><li className="breadcrumb-item"><Link to="/projects">Projects</Link></li><li aria-current="page" className="breadcrumb-item active">Resources</li></ol></div>
      </div></div></div>
      <div className="app-content"><div className="container-fluid vstack gap-4">
        <form aria-label="Resource filters" className="card card-body" onSubmit={(event) => event.preventDefault()}>
          <div className="row g-3">
            <div className="col-12 col-md-6"><label className="form-label" htmlFor="resource-kind">Resource kind</label><select className="form-select" id="resource-kind" onChange={(event) => setFilter("kind", event.target.value)} value={resourceKind ?? ""}><option value="">All kinds</option>{RESOURCE_KINDS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-md-6"><label className="form-label" htmlFor="resource-lifecycle">Lifecycle status</label><select className="form-select" id="resource-lifecycle" onChange={(event) => setFilter("lifecycle", event.target.value)} value={resourceLifecycleStatus ?? ""}><option value="">All statuses</option>{RESOURCE_LIFECYCLE_STATUSES.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
          </div>
        </form>
        <ProjectResourcesView
          browser={resources.data?.projectResources ?? null}
          errorMessage={errorMessage}
          loading={resources.isPending}
          onNextActiveLeases={(cursor) => setCursors((current) => ({ ...current, activeLeasesAfter: cursor }))}
          onNextResources={(cursor) => setCursors((current) => ({ ...current, resourcesAfter: cursor }))}
          onRetry={() => { void resources.refetch(); }}
          refreshing={resources.isFetching && resources.data !== undefined}
        />
      </div></div>
    </>
  );
}
