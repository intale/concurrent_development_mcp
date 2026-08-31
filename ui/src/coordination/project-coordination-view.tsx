import { Link } from "react-router-dom";
import type { CoordinationPresentationStatus } from "../gql/graphql.js";
import type { CoordinationDashboard } from "./project-coordination-model.js";
import { statusBadgeClass } from "./project-coordination-model.js";

export interface ProjectCoordinationViewProps {
  readonly dashboard: CoordinationDashboard | null;
  readonly errorMessage: string | null;
  readonly loading: boolean;
  readonly onNextChangeSets: (cursor: string) => void;
  readonly onNextDependencies: (cursor: string) => void;
  readonly onNextWorkItems: (cursor: string) => void;
  readonly onRetry: () => void;
  readonly refreshing: boolean;
}

function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}

function StatusBadge({ status }: { readonly status: CoordinationPresentationStatus }) {
  return <span className={`badge ${statusBadgeClass(status)}`}>{status.toLowerCase()}</span>;
}

export function ProjectCoordinationView(props: ProjectCoordinationViewProps) {
  if (props.loading && !props.dashboard) {
    return (
      <div className="card"><div className="card-body d-flex align-items-center gap-3" role="status">
        <span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" />
        <span>Loading coordination dashboard…</span>
      </div></div>
    );
  }

  if (props.errorMessage && !props.dashboard) {
    return (
      <div className="alert alert-danger" role="alert">
        <h2 className="h5">Coordination dashboard could not be loaded</h2>
        <p>{props.errorMessage}</p>
        <button className="btn btn-outline-light btn-sm" onClick={props.onRetry} type="button">Retry</button>
      </div>
    );
  }

  if (!props.dashboard) {
    return <div className="alert alert-warning" role="status">This project is not available in the latest projection.</div>;
  }

  const { project, changeSets, workItems, dependencies } = props.dashboard;
  const runningCount = workItems.nodes.filter((item) => item.presentationStatus === "RUNNING").length;
  const blockingCount = dependencies.nodes.filter((dependency) => dependency.blocking).length;

  return (
    <div className="vstack gap-4">
      {props.errorMessage ? (
        <div className="alert alert-warning" role="alert">
          The last available dashboard remains visible. {props.errorMessage}
          <button className="btn btn-outline-dark btn-sm ms-3" onClick={props.onRetry} type="button">Retry refresh</button>
        </div>
      ) : null}
      {props.refreshing ? <div className="alert alert-info mb-0" role="status">Refreshing latest available coordination facts…</div> : null}

      <div className="row g-3" aria-label="Coordination summary">
        <div className="col-12 col-md-4"><div className="small-box text-bg-primary"><div className="inner"><h2>{runningCount}</h2><p>Running work items on this page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-play-circle" /></span></div></div>
        <div className="col-12 col-md-4"><div className="small-box text-bg-warning"><div className="inner"><h2>{blockingCount}</h2><p>Blocking dependencies on this page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-sign-stop" /></span></div></div>
        <div className="col-12 col-md-4"><div className="small-box text-bg-success"><div className="inner"><h2>{changeSets.nodes.length}</h2><p>ChangeSets on this page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-diagram-3" /></span></div></div>
      </div>

      <section aria-labelledby="change-sets-heading" className="card card-outline card-primary">
        <div className="card-header"><h2 className="card-title" id="change-sets-heading">ChangeSets</h2></div>
        <div className="card-body vstack gap-3">
          {changeSets.nodes.length === 0 ? <p className="mb-0">No ChangeSets are available.</p> : changeSets.nodes.map((changeSet) => (
            <article className="border rounded p-3" key={changeSet.id}>
              <div className="d-flex flex-wrap justify-content-between gap-2"><h3 className="h5 mb-0">{changeSet.goal}</h3><span className="badge text-bg-secondary">{changeSet.domainStatus}</span></div>
              <p className="small text-body-secondary mb-2"><code>{changeSet.id}</code> · {changeSet.runningWorkItemCount} running · {changeSet.openWorkItemCount} open</p>
              <ul className="mb-0">{changeSet.acceptanceCriteria.map((criterion) => <li key={criterion}>{criterion}</li>)}</ul>
            </article>
          ))}
          {changeSets.pageInfo.hasNextPage && changeSets.pageInfo.endCursor ? <button className="btn btn-outline-primary align-self-start" onClick={() => props.onNextChangeSets(changeSets.pageInfo.endCursor as string)} type="button">Next ChangeSets page</button> : null}
        </div>
      </section>

      <section aria-labelledby="work-items-heading" className="card card-outline card-primary">
        <div className="card-header"><h2 className="card-title" id="work-items-heading">Scheduled work</h2></div>
        <div className="card-body p-0"><div className="table-responsive">
          <table aria-label="Scheduled work items" className="table table-hover align-middle mb-0">
            <thead className="table-light"><tr><th>Work item</th><th>Status</th><th>Agent</th><th>Attempt</th><th>Activity</th></tr></thead>
            <tbody>{workItems.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={5}>No work items match these filters.</td></tr> : workItems.nodes.map((item) => (
              <tr key={item.id}>
                <td><div className="fw-semibold">{item.goal}</div><code>{item.id}</code><div className="small text-body-secondary">domain: {item.domainStatus}</div></td>
                <td><StatusBadge status={item.presentationStatus} />{item.attemptStatus ? <div className="small mt-1">attempt: {item.attemptStatus}</div> : null}</td>
                <td>{item.activeAgentId ?? "—"}</td>
                <td>{item.activeAttemptId ? <code>{item.activeAttemptId}</code> : "—"}</td>
                <td className="text-nowrap">{formatted(item.attemptStartedAt ?? item.acquiredAt ?? item.madeReadyAt ?? item.completedAt ?? item.createdAt)}</td>
              </tr>
            ))}</tbody>
          </table>
        </div></div>
        {workItems.pageInfo.hasNextPage && workItems.pageInfo.endCursor ? <div className="card-footer"><button className="btn btn-outline-primary" onClick={() => props.onNextWorkItems(workItems.pageInfo.endCursor as string)} type="button">Next work-items page</button></div> : null}
      </section>

      <section aria-labelledby="dependencies-heading" className="card card-outline card-warning">
        <div className="card-header"><h2 className="card-title" id="dependencies-heading">Dependencies and blockers</h2></div>
        <div className="card-body p-0"><div className="table-responsive">
          <table aria-label="Work item dependencies" className="table table-hover align-middle mb-0">
            <thead className="table-light"><tr><th>Dependency</th><th>Producer</th><th>Consumer</th><th>State</th></tr></thead>
            <tbody>{dependencies.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={4}>No dependencies match these filters.</td></tr> : dependencies.nodes.map((dependency) => (
              <tr key={dependency.id}><td><code>{dependency.id}</code><div className="small">{dependency.dependencyKind}</div></td><td><code>{dependency.producerWorkItemId}</code></td><td><code>{dependency.consumerWorkItemId}</code></td><td>{dependency.blocking ? <span className="badge text-bg-warning">blocking</span> : <span className="badge text-bg-success">satisfied</span>}</td></tr>
            ))}</tbody>
          </table>
        </div></div>
        {dependencies.pageInfo.hasNextPage && dependencies.pageInfo.endCursor ? <div className="card-footer"><button className="btn btn-outline-primary" onClick={() => props.onNextDependencies(dependencies.pageInfo.endCursor as string)} type="button">Next dependencies page</button></div> : null}
      </section>

      <p className="small text-body-secondary mb-0">Viewing latest available projections for <strong>{project.name ?? project.id}</strong> in <code>{project.scope}</code>. Projection freshness never gates availability.</p>
      <div><Link className="btn btn-outline-secondary" to={`/projects?scope=${encodeURIComponent(project.scope)}`}>Back to project catalog</Link></div>
    </div>
  );
}
