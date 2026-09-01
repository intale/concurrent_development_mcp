import { useEffect, useMemo, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import {
  fetchProjectWorkspace,
  PROJECT_REPOSITORY_PAGE_SIZE,
  projectWorkspaceQueryKey
} from "./project-catalog-api.js";
import { useProjectWorkspace } from "./project-workspace-shell.js";
import { ProjectOverviewView } from "./project-overview-view.js";
import type { ProjectOverviewRepository } from "./project-overview-view.js";

export function ProjectOverviewPage() {
  const { project: shellProject, projectRef } = useProjectWorkspace();
  const [searchParams, setSearchParams] = useSearchParams();
  const after = searchParams.get("membersAfter");
  const pageNumber = searchParams.getAll("membersTrail").length + 1;
  const headingRef = useRef<HTMLHeadingElement>(null);
  const overview = useQuery({
    queryKey: projectWorkspaceQueryKey(projectRef, PROJECT_REPOSITORY_PAGE_SIZE, after),
    queryFn: ({ signal }) => fetchProjectWorkspace(
      projectRef,
      PROJECT_REPOSITORY_PAGE_SIZE,
      after,
      signal
    ),
    placeholderData: (previousData) => previousData
  });

  useEffect(() => {
    document.title = `${shellProject.displayLabel} overview · Coordinator`;
    headingRef.current?.focus();
  }, [shellProject.projectRef]);

  const project = overview.data?.project;
  const repositories = useMemo<readonly ProjectOverviewRepository[]>(() => (
    project?.repositories.nodes.map((repository) => ({
      id: repository.id,
      displayName: repository.displayName ?? repository.paths[0] ?? repository.id,
      paths: repository.paths,
      registeredAt: repository.registeredAt,
      remotes: repository.remotes
    })) ?? []
  ), [project]);

  const goNext = () => {
    const cursor = project?.repositories.pageInfo.endCursor;
    if (!cursor) return;
    const next = new URLSearchParams(searchParams);
    next.append("membersTrail", next.get("membersAfter") ?? "");
    next.set("membersAfter", cursor);
    setSearchParams(next);
  };

  const goPrevious = () => {
    const previous = new URLSearchParams(searchParams);
    const trail = previous.getAll("membersTrail");
    const cursor = trail.pop();
    previous.delete("membersTrail");
    trail.forEach((value) => previous.append("membersTrail", value));
    if (cursor) previous.set("membersAfter", cursor);
    else previous.delete("membersAfter");
    setSearchParams(previous);
  };

  return (
    <section aria-labelledby="project-overview-heading" className="vstack gap-4">
      <div>
        <h2 className="h3 mb-1" id="project-overview-heading" ref={headingRef} tabIndex={-1}>
          Overview
        </h2>
        <p className="text-body-secondary mb-0">
          Project identity and Repository membership from the latest available read models.
        </p>
      </div>
      <ProjectOverviewView
        canGoBack={searchParams.has("membersTrail")}
        errorMessage={overview.error instanceof Error ? overview.error.message : null}
        hasNextPage={project?.repositories.pageInfo.hasNextPage ?? false}
        loading={overview.isPending}
        onNext={goNext}
        onPrevious={goPrevious}
        onRetry={() => { void overview.refetch(); }}
        pageNumber={pageNumber}
        projectRef={projectRef}
        refreshing={overview.isFetching && overview.data !== undefined}
        repositories={repositories}
        repositoryCount={project?.repositoryCount ?? shellProject.repositoryCount}
      />
    </section>
  );
}
