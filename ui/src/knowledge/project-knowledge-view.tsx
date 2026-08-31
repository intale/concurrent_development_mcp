import { Link } from "react-router-dom";
import type { ArtifactRelationDirection, DevelopmentArtifactRelationKind } from "../gql/graphql.js";
import { ARTIFACT_RELATIONS, humanized, RELATION_DIRECTIONS } from "./project-knowledge-model.js";
import type {
  ProjectArtifact,
  ProjectKnowledge,
  ProjectSkill,
  ProjectSkillAsset
} from "./project-knowledge-model.js";

export interface ProjectKnowledgeViewProps {
  readonly artifact: ProjectArtifact | null;
  readonly asset: ProjectSkillAsset | null;
  readonly catalog: ProjectKnowledge | null;
  readonly direction: ArtifactRelationDirection;
  readonly errorMessage: string | null;
  readonly hrefForArtifact: (artifactId: string) => string;
  readonly hrefForAsset: (path: string) => string;
  readonly hrefForSkill: (name: string) => string;
  readonly loading: boolean;
  readonly onDirection: (direction: string) => void;
  readonly onNextArtifacts: (cursor: string) => void;
  readonly onNextRelations: (cursor: string) => void;
  readonly onNextSkills: (cursor: string) => void;
  readonly onRelation: (relation: string) => void;
  readonly onRetry: () => void;
  readonly refreshing: boolean;
  readonly relation: DevelopmentArtifactRelationKind | undefined;
  readonly skill: ProjectSkill | null;
}

function formatted(value: string | null | undefined): string {
  return value ? new Date(value).toLocaleString() : "—";
}

function Content({ base64, text }: { readonly base64?: string | null; readonly text?: string | null }) {
  if (text !== null && text !== undefined) return <pre className="border rounded bg-body-tertiary p-3 mb-0 text-wrap">{text}</pre>;
  if (base64) return <div className="alert alert-secondary mb-0">Binary content is available as Base64 through GraphQL.</div>;
  return <div className="text-body-secondary">No content is available in this projection.</div>;
}

export function ProjectKnowledgeView(props: ProjectKnowledgeViewProps) {
  if (props.loading && !props.catalog) {
    return <div className="card"><div className="card-body d-flex align-items-center gap-3" role="status"><span aria-hidden="true" className="spinner-border spinner-border-sm text-primary" /><span>Loading project knowledge…</span></div></div>;
  }
  if (props.errorMessage && !props.catalog) {
    return <div className="alert alert-danger" role="alert"><h2 className="h5">Project knowledge could not be loaded</h2><p>{props.errorMessage}</p><button className="btn btn-outline-light btn-sm" onClick={props.onRetry} type="button">Retry</button></div>;
  }
  if (!props.catalog) {
    return <div className="alert alert-warning" role="status">This project is not available in the latest projection.</div>;
  }

  const { artifacts, project, skills } = props.catalog;
  return (
    <div className="vstack gap-4">
      {props.errorMessage ? <div className="alert alert-warning" role="alert">The last available knowledge view remains visible. {props.errorMessage}<button className="btn btn-outline-dark btn-sm ms-3" onClick={props.onRetry} type="button">Retry refresh</button></div> : null}
      {props.refreshing ? <div className="alert alert-info mb-0" role="status">Refreshing latest available knowledge facts…</div> : null}

      <div aria-label="Knowledge summary" className="row g-3">
        <div className="col-12 col-md-6"><div className="small-box text-bg-primary"><div className="inner"><h2>{skills.nodes.length}</h2><p>Current Skills on this page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-journal-code" /></span></div></div>
        <div className="col-12 col-md-6"><div className="small-box text-bg-info"><div className="inner"><h2>{artifacts.nodes.length}</h2><p>Artifacts on this page</p></div><span aria-hidden="true" className="small-box-icon"><i className="bi bi-diagram-2" /></span></div></div>
      </div>

      <section aria-labelledby="skills-heading" className="card card-outline card-primary">
        <div className="card-header"><h2 className="card-title" id="skills-heading">Current Skills</h2></div>
        <div className="card-body p-0"><div className="table-responsive"><table aria-label="Current Skills" className="table table-hover align-middle mb-0"><thead className="table-light"><tr><th>Name</th><th>Revision</th><th>Assets</th><th>Published</th></tr></thead><tbody>
          {skills.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={4}>No Skills match this filter.</td></tr> : skills.nodes.map((item) => <tr key={item.id}><td><Link className="fw-semibold" to={props.hrefForSkill(item.name)}>{item.name}</Link><div className="small text-body-secondary">{item.description}</div></td><td>{item.revision}</td><td>{item.assetCount}</td><td className="text-nowrap">{formatted(item.publishedAt)}</td></tr>)}
        </tbody></table></div></div>
        {skills.pageInfo.hasNextPage && skills.pageInfo.endCursor ? <div className="card-footer"><button className="btn btn-outline-primary" onClick={() => props.onNextSkills(skills.pageInfo.endCursor as string)} type="button">Next Skills page</button></div> : null}
      </section>

      {props.skill ? <section aria-labelledby="skill-detail-heading" className="card card-outline card-primary"><div className="card-header"><h2 className="card-title" id="skill-detail-heading">{props.skill.skill.name} · revision {props.skill.skill.revision}</h2></div><div className="card-body vstack gap-3"><p className="mb-0">{props.skill.skill.description}</p><Content text={props.skill.skill.instructions} /><div><h3 className="h6">Assets</h3><div className="list-group">{props.skill.skill.assets.length === 0 ? <span className="list-group-item text-body-secondary">No assets.</span> : props.skill.skill.assets.map((item) => <Link className="list-group-item list-group-item-action d-flex justify-content-between gap-3" key={item.path} to={props.hrefForAsset(item.path)}><code>{item.path}</code><span className="text-body-secondary">{item.mediaType} · {item.byteSize} bytes</span></Link>)}</div></div></div></section> : null}

      {props.asset ? <section aria-labelledby="asset-detail-heading" className="card card-outline card-secondary"><div className="card-header"><h2 className="card-title" id="asset-detail-heading">Skill asset · {props.asset.asset.path}</h2></div><div className="card-body vstack gap-3"><p className="small text-body-secondary mb-0">Revision {props.asset.asset.revision} · {props.asset.asset.mediaType} · {props.asset.asset.byteSize} bytes · digest <code>{props.asset.asset.contentDigest}</code></p><Content base64={props.asset.asset.base64} text={props.asset.asset.text} /></div></section> : null}

      <section aria-labelledby="artifacts-heading" className="card card-outline card-info">
        <div className="card-header"><h2 className="card-title" id="artifacts-heading">Development Artifacts</h2></div>
        <div className="card-body p-0"><div className="table-responsive"><table aria-label="Development Artifacts" className="table table-hover align-middle mb-0"><thead className="table-light"><tr><th>Artifact</th><th>Classification</th><th>Source</th><th>Observed</th></tr></thead><tbody>
          {artifacts.nodes.length === 0 ? <tr><td className="text-center py-4" colSpan={4}>No Artifacts match these filters.</td></tr> : artifacts.nodes.map((item) => <tr key={item.id}><td><Link className="fw-semibold" to={props.hrefForArtifact(item.id)}>{item.title}</Link><div className="small text-body-secondary">{item.labels.join(", ") || "No labels"}</div></td><td><span className="badge text-bg-info">{humanized(item.kind)}</span><div className="small mt-1">revision {item.classificationRevision}</div></td><td><div>{humanized(item.source.kind)}</div><code>{item.source.locator}</code></td><td className="text-nowrap">{formatted(item.observedAt)}</td></tr>)}
        </tbody></table></div></div>
        {artifacts.pageInfo.hasNextPage && artifacts.pageInfo.endCursor ? <div className="card-footer"><button className="btn btn-outline-info" onClick={() => props.onNextArtifacts(artifacts.pageInfo.endCursor as string)} type="button">Next Artifacts page</button></div> : null}
      </section>

      {props.artifact ? <section aria-labelledby="artifact-detail-heading" className="card card-outline card-info"><div className="card-header"><h2 className="card-title" id="artifact-detail-heading">{props.artifact.artifact.title}</h2></div><div className="card-body vstack gap-3"><div className="row g-3"><div className="col-12 col-lg-6"><h3 className="h6">Classification</h3><p className="mb-1"><span className="badge text-bg-info">{humanized(props.artifact.artifact.kind)}</span> {props.artifact.artifact.labels.map((label) => <span className="badge text-bg-secondary ms-1" key={label}>{label}</span>)}</p><p className="small text-body-secondary mb-0">Observation <code>{props.artifact.artifact.observationId}</code> · revision {props.artifact.artifact.classificationRevision}</p></div><div className="col-12 col-lg-6"><h3 className="h6">Provenance</h3><p className="mb-0">{humanized(props.artifact.artifact.source.kind)} · <code>{props.artifact.artifact.source.locator}</code></p><p className="small text-body-secondary mb-0">Observed {formatted(props.artifact.artifact.source.observedAt)} by {props.artifact.artifact.source.collector}</p></div></div><Content base64={props.artifact.content.base64} text={props.artifact.content.text} /><div><div className="d-flex flex-wrap align-items-end gap-3 mb-3"><div><label className="form-label" htmlFor="relation-direction">Direction</label><select className="form-select" id="relation-direction" onChange={(event) => props.onDirection(event.target.value)} value={props.direction}>{RELATION_DIRECTIONS.map((value) => <option key={value} value={value}>{humanized(value)}</option>)}</select></div><div><label className="form-label" htmlFor="relation-kind">Relationship</label><select className="form-select" id="relation-kind" onChange={(event) => props.onRelation(event.target.value)} value={props.relation ?? ""}><option value="">All relationships</option>{ARTIFACT_RELATIONS.map((value) => <option key={value} value={value}>{humanized(value)}</option>)}</select></div></div><h3 className="h6">Active relationships</h3><div className="list-group">{props.artifact.relationships.nodes.length === 0 ? <span className="list-group-item text-body-secondary">No active relationships match these filters.</span> : props.artifact.relationships.nodes.map((item) => <Link className="list-group-item list-group-item-action" key={`${item.direction}:${item.id}`} to={props.hrefForArtifact(item.peerId)}><div className="d-flex justify-content-between gap-3"><span><span className="badge text-bg-secondary me-2">{humanized(item.direction)}</span>{humanized(item.displayRelation)}</span><span className="small text-body-secondary">{formatted(item.declaredAt)}</span></div><div className="mt-1 fw-semibold">{item.peerArtifact?.title ?? item.targetName ?? item.peerId}</div><code>{item.peerArtifact?.source.locator ?? item.normalizedLocator ?? item.path ?? item.peerId}</code></Link>)}</div>{props.artifact.relationships.pageInfo.hasNextPage && props.artifact.relationships.pageInfo.endCursor ? <button className="btn btn-outline-info mt-3" onClick={() => props.onNextRelations(props.artifact?.relationships.pageInfo.endCursor as string)} type="button">Next relationships page</button> : null}</div></div></section> : null}

      <p className="small text-body-secondary mb-0">Viewing latest available projections for <strong>{project.name ?? project.id}</strong> in <code>{project.scope}</code>. Historical Skill revisions and superseded Artifact edges are intentionally absent.</p>
      <div className="d-flex flex-wrap gap-2"><Link className="btn btn-outline-primary" to={`/projects/${project.id}/coordination`}>View coordination</Link><Link className="btn btn-outline-primary" to={`/projects/${project.id}/resources`}>View resources</Link><Link className="btn btn-outline-secondary" to={`/projects?scope=${encodeURIComponent(project.scope)}`}>Back to project catalog</Link></div>
    </div>
  );
}
