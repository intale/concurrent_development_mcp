import type { ProjectRow } from "./project-catalog-model.js";
import { Link } from "react-router-dom";

export interface ProjectCatalogViewProps {
  readonly canGoBack: boolean;
  readonly errorMessage: string | null;
  readonly hasNextPage: boolean;
  readonly loading: boolean;
  readonly onNext: () => void;
  readonly onPrevious: () => void;
  readonly onRetry: () => void;
  readonly refreshing: boolean;
  readonly rows: readonly ProjectRow[];
  readonly scopeRequired: boolean;
  readonly showingPreviousData: boolean;
}

export function ProjectCatalogView(props: ProjectCatalogViewProps) {
  if (props.scopeRequired) {
    return (
      <div className="card card-outline card-primary">
        <div className="card-header"><h2 className="card-title">Select a project scope</h2></div>
        <div className="card-body text-body-secondary">
          Enter an exact project scope to load its latest available catalog.
        </div>
      </div>
    );
  }

  if (props.loading && props.rows.length === 0) {
    return (
      <div className="card">
        <div className="card-body d-flex align-items-center gap-3" aria-live="polite" role="status">
          <span className="spinner-border spinner-border-sm text-primary" aria-hidden="true" />
          <span>Loading projects…</span>
        </div>
      </div>
    );
  }

  if (props.errorMessage && props.rows.length === 0) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5"><i aria-hidden="true" className="bi bi-exclamation-triangle me-2" />Projects could not be loaded</h2>
        <div className="d-flex align-items-center justify-content-between gap-3">
          <span>{props.errorMessage}</span>
          <button className="btn btn-outline-light btn-sm" onClick={props.onRetry} type="button">Retry</button>
        </div>
      </div>
    );
  }

  if (props.rows.length === 0) {
    return (
      <div className="card">
        <div className="card-header"><h2 className="card-title">No available projects</h2></div>
        <div className="card-body">No projects are currently available for this exact scope.</div>
      </div>
    );
  }

  return (
    <div className="vstack gap-3">
      {props.errorMessage ? (
        <div className="alert alert-warning" role="alert">
          <h2 className="h5"><i aria-hidden="true" className="bi bi-arrow-clockwise me-2" />Refresh failed</h2>
          <div className="d-flex align-items-center justify-content-between gap-3">
            <span>The last available projects remain visible. {props.errorMessage}</span>
            <button className="btn btn-outline-dark btn-sm" onClick={props.onRetry} type="button">
              Retry refresh
            </button>
          </div>
        </div>
      ) : null}
      {props.refreshing ? (
        <div className="alert alert-info mb-0">
          <i aria-hidden="true" className="bi bi-arrow-repeat me-2" />
          <span aria-live="polite" role="status">
            {props.showingPreviousData
              ? "Refreshing while the last available project page remains visible…"
              : "Refreshing latest available projects…"}
          </span>
        </div>
      ) : null}
      <p className="small text-body-secondary mb-0">
        Showing {props.rows.length} {props.rows.length === 1 ? "project" : "projects"} from this available page.
      </p>
      <div className="card card-outline card-primary">
        <div className="card-header">
          <h2 className="card-title"><i aria-hidden="true" className="bi bi-folder2-open me-2" />Available projects</h2>
        </div>
        <div className="card-body p-0">
          <div className="table-responsive">
            <table className="table table-hover align-middle mb-0" aria-label="Projects">
            <thead className="table-light">
              <tr>
                <th scope="col">Project</th>
                <th scope="col">Exact scope</th>
                <th scope="col">Paths</th>
                <th scope="col">Remotes</th>
                <th scope="col">Registered</th>
              </tr>
            </thead>
            <tbody>
              {props.rows.map((row) => (
                <tr key={row.id}>
                  <td className="fw-semibold"><Link to={`/projects/${row.id}/coordination`}>{row.name}</Link></td>
                  <td><code>{row.scope}</code></td>
                  <td>{row.paths || "—"}</td>
                  <td>{row.remotes || "—"}</td>
                  <td className="text-nowrap">{row.registeredAt}</td>
                </tr>
              ))}
            </tbody>
            </table>
          </div>
        </div>
      </div>
      <div className="d-flex justify-content-between">
        <button className="btn btn-outline-secondary" disabled={!props.canGoBack} onClick={props.onPrevious} type="button">
          Previous page
        </button>
        <button className="btn btn-outline-primary" disabled={!props.hasNextPage} onClick={props.onNext} type="button">
          Next page
        </button>
      </div>
    </div>
  );
}
