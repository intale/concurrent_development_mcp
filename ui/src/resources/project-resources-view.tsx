import { Link } from "react-router-dom";
import type { ProjectResourceBrowser } from "./project-resources-model.js";
import { lifecycleBadgeClass } from "./project-resources-model.js";

export interface ProjectResourcesViewProps {
  readonly browser: ProjectResourceBrowser | null;
  readonly errorMessage: string | null;
  readonly loading: boolean;
  readonly onNextActiveLeases: (cursor: string) => void;
  readonly onNextResources: (cursor: string) => void;
  readonly onRetry: () => void;
  readonly refreshing: boolean;
}

function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}

export function ProjectResourcesView(props: ProjectResourcesViewProps) {
  if (props.loading && !props.browser) {
    return (
      <div className="card"><div className="card-body d-flex align-items-center gap-3" role="status">
        <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
        <span>Loading project resources…</span>
      </div></div>
    );
  }

  if (props.errorMessage && !props.browser) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5">Project resources could not be loaded</h2>
        <p>{props.errorMessage}</p>
        <button className="btn btn-outline-light btn-sm" onClick={props.onRetry} type="button">Retry</button>
      </div>
    );
  }

  if (!props.browser) {
    return <div className="alert alert-warning" role="status">This project is not available in the latest projection.</div>;
  }

  const { activeLeases, project, resources } = props.browser;

  return (
    <div className="vstack gap-4">
      {props.errorMessage ? (
        <div className="alert alert-warning" role="alert">
          The last available resource view remains visible. {props.errorMessage}
          <button className="btn btn-outline-dark btn-sm ms-3" onClick={props.onRetry} type="button">Retry refresh</button>
        </div>
      ) : null}
      {props.refreshing ? <div className="alert alert-info mb-0" role="status">Refreshing latest available resource facts…</div> : null}

      <div aria-label="Resource summary" className="row g-3">
        <div className="col-12 col-md-6"><div className="small-box text-bg-primary"><div className="inner"><h2>{resources.nodes.length}</h2><p>Resources on this page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-files" /></span></div></div>
        <div className="col-12 col-md-6"><div className="small-box text-bg-warning"><div className="inner"><h2>{activeLeases.nodes.length}</h2><p>Active leases on this page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-lock" /></span></div></div>
      </div>

      <section aria-labelledby="resources-heading" className="card card-outline card-primary">
        <div className="card-header"><h2 className="card-title" id="resources-heading">Resource inventory</h2></div>
        <div className="card-body p-0"><div className="table-responsive">
          <table aria-label="Project resources" className="table table-hover align-middle mb-0">
            <thead className="table-light"><tr><th>Path</th><th>Kind</th><th>Lifecycle</th><th>Last transition</th></tr></thead>
            <tbody>{resources.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={4}>No resources match these filters.</td></tr> : resources.nodes.map((resource) => (
              <tr key={resource.id}>
                <td><code>{resource.path}</code><div className="small text-body-secondary">{resource.id}</div></td>
                <td>{resource.kind.toLowerCase()}</td>
                <td><span className={`badge ${lifecycleBadgeClass(resource.lifecycleStatus)}`}>{resource.lifecycleStatus.toLowerCase()}</span>{resource.unbindingReason ? <div className="small mt-1">{resource.unbindingReason}</div> : null}</td>
                <td className="text-nowrap">{formatted(resource.lastTransitionAt ?? resource.registeredAt)}</td>
              </tr>
            ))}</tbody>
          </table>
        </div></div>
        {resources.pageInfo.hasNextPage && resources.pageInfo.endCursor ? <div className="card-footer"><button className="btn btn-outline-primary" onClick={() => props.onNextResources(resources.pageInfo.endCursor as string)} type="button">Next resources page</button></div> : null}
      </section>

      <section aria-labelledby="leases-heading" className="card card-outline card-warning">
        <div className="card-header"><h2 className="card-title" id="leases-heading">Active resource leases</h2></div>
        <div className="card-body p-0"><div className="table-responsive">
          <table aria-label="Active resource leases" className="table table-hover align-middle mb-0">
            <thead className="table-light"><tr><th>Resource</th><th>Owner</th><th>Coordination</th><th>Fence</th><th>Expires</th></tr></thead>
            <tbody>{activeLeases.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={5}>No active lease facts are available.</td></tr> : activeLeases.nodes.map((lease) => (
              <tr key={lease.id}>
                <td><code>{lease.resourcePath}</code><div className="small text-body-secondary">{lease.resourceKind.toLowerCase()} · {lease.resourceId}</div></td>
                <td><div className="fw-semibold">{lease.agentId}</div><code>{lease.attemptId}</code></td>
                <td><div><code>{lease.workItemId}</code></div><div className="small text-body-secondary">{lease.changeSetId}</div></td>
                <td><code>{lease.fencingToken}</code></td>
                <td className="text-nowrap">{formatted(lease.expiresAt)}</td>
              </tr>
            ))}</tbody>
          </table>
        </div></div>
        <div className="card-footer d-flex flex-wrap align-items-center justify-content-between gap-2">
          <span className="small text-body-secondary">Active as of {formatted(activeLeases.asOf)}. Ownership is derived only from projected lease facts.</span>
          {activeLeases.pageInfo.hasNextPage && activeLeases.pageInfo.endCursor ? <button className="btn btn-outline-warning" onClick={() => props.onNextActiveLeases(activeLeases.pageInfo.endCursor as string)} type="button">Next active leases page</button> : null}
        </div>
      </section>

      <p className="small text-body-secondary mb-0">Viewing latest available projections for <strong>{project.name ?? project.id}</strong> in <code>{project.scope}</code>. Projection freshness never gates availability.</p>
      <div className="d-flex flex-wrap gap-2">
        <Link className="btn btn-outline-primary" to={`/projects/${project.id}/coordination`}>View coordination</Link>
        <Link className="btn btn-outline-primary" to={`/projects/${project.id}/knowledge`}>View knowledge</Link>
        <Link className="btn btn-outline-primary" to={`/projects/${project.id}/governance`}>View governance</Link>
        <Link className="btn btn-outline-secondary" to={`/projects?scope=${encodeURIComponent(project.scope)}`}>Back to project catalog</Link>
      </div>
    </div>
  );
}
