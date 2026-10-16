import { createContext, useContext, useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { Link, Outlet, useLocation, useParams } from "react-router-dom";
import { PROJECT_NAVIGATION, projectPath } from "../navigation.js";
import type { ProjectWorkspaceQuery } from "../gql/graphql.js";
import {
  fetchProjectWorkspace,
  PROJECT_REPOSITORY_PREVIEW_SIZE,
  projectWorkspaceQueryKey
} from "./project-catalog-api.js";

const REFRESH_INTERVAL_MS = 15_000;

export type ProjectWorkspace = NonNullable<ProjectWorkspaceQuery["project"]>;

export interface ProjectWorkspaceContextValue {
  readonly project: ProjectWorkspace;
  readonly projectRef: string;
}

const ProjectWorkspaceContext = createContext<ProjectWorkspaceContextValue | null>(null);

export function useProjectWorkspace(): ProjectWorkspaceContextValue {
  const workspace = useContext(ProjectWorkspaceContext);
  if (!workspace) throw new Error("Project workspace context is unavailable");
  return workspace;
}

export function ProjectWorkspaceShell() {
  const { projectRef = "" } = useParams<{ projectRef: string }>();
  const location = useLocation();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const basePath = projectPath(projectRef);
  const sectionPath = `/${location.pathname.slice(basePath.length + 1).split("/")[0] ?? ""}`;
  const section = PROJECT_NAVIGATION.flatMap((group) => group.items).find((item) => item.path === sectionPath);
  const workspace = useQuery({
    queryKey: projectWorkspaceQueryKey(projectRef, PROJECT_REPOSITORY_PREVIEW_SIZE, null),
    queryFn: ({ signal }) => fetchProjectWorkspace(
      projectRef,
      PROJECT_REPOSITORY_PREVIEW_SIZE,
      null,
      signal
    ),
    enabled: projectRef.length > 0,
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const project = workspace.data?.project;

  useEffect(() => {
    if (!project || !projectHeadingOwnsFocus(location.pathname, basePath)) return;
    document.title = `${project.displayLabel} · Coordinator`;
    headingRef.current?.focus();
  }, [basePath, location.pathname, project?.projectRef]);

  if (workspace.isPending) {
    return (
      <div className="app-content">
        <div className="container-fluid py-4">
          <div aria-live="polite" className="card" role="status">
            <div className="card-body d-flex align-items-center gap-3">
              <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
              <span>Loading Project workspace…</span>
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (!project) {
    const message = workspace.error instanceof Error ? workspace.error.message : null;
    return (
      <div className="app-content">
        <div className="container-fluid py-4">
          <div className="alert alert-warning" role="alert">
            <h1 className="h4">Project is unavailable</h1>
            <p>
              {message ?? "No available project matches this exact scope."}
            </p>
            <div className="d-flex flex-wrap gap-2">
              {message ? (
                <button
                  className="btn btn-warning"
                  onClick={() => { void workspace.refetch(); }}
                  type="button"
                >
                  Retry
                </button>
              ) : null}
              <Link className="btn btn-outline-dark" to="/projects">Return to Projects</Link>
            </div>
          </div>
        </div>
      </div>
    );
  }

  const context = { project, projectRef } satisfies ProjectWorkspaceContextValue;

  return (
    <ProjectWorkspaceContext.Provider value={context}>
      <div className="app-content-header pb-0">
        <div className="container-fluid">
          <nav aria-label="Breadcrumb">
            <ol className="breadcrumb mb-2">
              <li className="breadcrumb-item"><Link to="/projects">Projects</Link></li>
              {section ? <><li className="breadcrumb-item"><Link to={basePath}>{project.displayLabel}</Link></li><li aria-current="page" className="breadcrumb-item active">{section.label}</li></> : <li aria-current="page" className="breadcrumb-item active">{project.displayLabel}</li>}
            </ol>
          </nav>
          <div className="d-flex flex-column flex-lg-row align-items-lg-start justify-content-between gap-3">
            <div>
              <h1 className="h4 mb-1 d-inline-block" ref={headingRef} tabIndex={-1}>{project.displayLabel}</h1>
              <div className="small text-body-secondary text-break">Scope: {project.scope}</div>
            </div>
            <div className="text-lg-end">
              <span className="badge text-bg-secondary">
                {project.repositoryCount} {project.repositoryCount === 1 ? "Repository" : "Repositories"}
              </span>
            </div>
          </div>
          {workspace.error ? (
            <div className="alert alert-warning mt-3 mb-0" role="alert">
              The last available Project identity remains visible while refresh is retried.
            </div>
          ) : null}
        </div>
      </div>
      <div className="app-content pt-3">
        <div className="container-fluid"><Outlet /></div>
      </div>
    </ProjectWorkspaceContext.Provider>
  );
}

export function projectHeadingOwnsFocus(pathname: string, basePath: string): boolean {
  return pathname === basePath;
}
