import { useQuery } from "@tanstack/react-query";
import { Link, useParams, useSearchParams } from "react-router-dom";
import type {
  ArtifactRelationDirection,
  DevelopmentArtifactKind,
  DevelopmentArtifactRelationKind,
  DevelopmentArtifactSourceKind
} from "../gql/graphql.js";
import {
  fetchProjectArtifact,
  fetchProjectKnowledge,
  fetchProjectSkill,
  fetchProjectSkillAsset
} from "./project-knowledge-api.js";
import {
  ARTIFACT_KINDS,
  ARTIFACT_RELATIONS,
  ARTIFACT_SOURCE_KINDS,
  preserveKnowledgeForProject,
  RELATION_DIRECTIONS
} from "./project-knowledge-model.js";
import { ProjectKnowledgeView } from "./project-knowledge-view.js";

const REFRESH_INTERVAL_MS = 15_000;

export function ProjectKnowledgePage() {
  const { repositoryId = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const skillName = searchParams.get("skillName")?.trim() || undefined;
  const labels = (searchParams.get("labels") ?? "").split(",").map((label) => label.trim()).filter(Boolean);
  const requestedKind = searchParams.get("artifactKind") as DevelopmentArtifactKind | null;
  const artifactKind = ARTIFACT_KINDS.some(({ value }) => value === requestedKind) ? requestedKind ?? undefined : undefined;
  const requestedSourceKind = searchParams.get("sourceKind") as DevelopmentArtifactSourceKind | null;
  const artifactSourceKind = ARTIFACT_SOURCE_KINDS.some(({ value }) => value === requestedSourceKind)
    ? requestedSourceKind ?? undefined
    : undefined;
  const selectedSkill = searchParams.get("skill") ?? undefined;
  const selectedAsset = searchParams.get("asset") ?? undefined;
  const selectedArtifact = searchParams.get("artifact") ?? undefined;
  const requestedDirection = searchParams.get("direction") as ArtifactRelationDirection | null;
  const direction = RELATION_DIRECTIONS.includes(requestedDirection ?? "BOTH")
    ? requestedDirection ?? "BOTH"
    : "BOTH";
  const requestedRelation = searchParams.get("relation") as DevelopmentArtifactRelationKind | null;
  const relation = ARTIFACT_RELATIONS.includes(requestedRelation ?? "REFERENCES")
    ? requestedRelation ?? undefined
    : undefined;
  const filters = {
    artifactLabels: labels,
    ...(artifactKind ? { artifactKind } : {}),
    ...(artifactSourceKind ? { artifactSourceKind } : {}),
    ...(skillName ? { skillName } : {})
  };
  const cursors = {
    ...(searchParams.get("artifactsAfter") ? { artifactsAfter: searchParams.get("artifactsAfter") as string } : {}),
    ...(searchParams.get("skillsAfter") ? { skillsAfter: searchParams.get("skillsAfter") as string } : {})
  };

  const catalog = useQuery({
    queryKey: ["project-knowledge", repositoryId, filters, cursors],
    queryFn: ({ signal }) => fetchProjectKnowledge(repositoryId, filters, cursors, signal),
    enabled: repositoryId.length > 0,
    placeholderData: (previousData, previousQuery) => (
      preserveKnowledgeForProject(previousData, previousQuery?.queryKey, repositoryId)
    ),
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const skill = useQuery({
    queryKey: ["project-skill", repositoryId, selectedSkill],
    queryFn: ({ signal }) => fetchProjectSkill(repositoryId, selectedSkill ?? "", signal),
    enabled: repositoryId.length > 0 && selectedSkill !== undefined,
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const asset = useQuery({
    queryKey: ["project-skill-asset", repositoryId, selectedSkill, selectedAsset],
    queryFn: ({ signal }) => fetchProjectSkillAsset(repositoryId, selectedSkill ?? "", selectedAsset ?? "", signal),
    enabled: repositoryId.length > 0 && selectedSkill !== undefined && selectedAsset !== undefined,
    refetchInterval: REFRESH_INTERVAL_MS
  });
  const artifact = useQuery({
    queryKey: ["project-artifact", repositoryId, selectedArtifact, direction, relation, searchParams.get("relationsAfter")],
    queryFn: ({ signal }) => fetchProjectArtifact(
      repositoryId,
      selectedArtifact ?? "",
      {
        direction,
        ...(relation ? { relation } : {}),
        ...(searchParams.get("relationsAfter") ? { relationsAfter: searchParams.get("relationsAfter") as string } : {})
      },
      signal
    ),
    enabled: repositoryId.length > 0 && selectedArtifact !== undefined,
    refetchInterval: REFRESH_INTERVAL_MS
  });

  const update = (changes: Readonly<Record<string, string | null>>) => {
    const next = new URLSearchParams(searchParams);
    Object.entries(changes).forEach(([name, value]) => value ? next.set(name, value) : next.delete(name));
    setSearchParams(next);
  };
  const href = (changes: Readonly<Record<string, string | null>>) => {
    const next = new URLSearchParams(searchParams);
    Object.entries(changes).forEach(([name, value]) => value ? next.set(name, value) : next.delete(name));
    return `/projects/${repositoryId}/knowledge?${next.toString()}`;
  };
  const errors = [catalog.error, skill.error, asset.error, artifact.error].filter((error): error is Error => error instanceof Error);
  const retry = () => {
    void catalog.refetch();
    if (selectedSkill) void skill.refetch();
    if (selectedSkill && selectedAsset) void asset.refetch();
    if (selectedArtifact) void artifact.refetch();
  };

  return (
    <>
      <div className="app-content-header"><div className="container-fluid"><div className="row align-items-center">
        <div className="col-sm-6"><h1 className="mb-0">Project knowledge</h1></div>
        <div className="col-sm-6"><ol className="breadcrumb float-sm-end mb-0"><li className="breadcrumb-item"><Link to="/projects">Projects</Link></li><li aria-current="page" className="breadcrumb-item active">Knowledge</li></ol></div>
      </div></div></div>
      <div className="app-content"><div className="container-fluid vstack gap-4">
        <form aria-label="Knowledge filters" className="card card-body" onSubmit={(event) => event.preventDefault()}>
          <div className="row g-3">
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="skill-name">Skill name</label><input className="form-control" id="skill-name" onChange={(event) => update({ skillName: event.target.value, skillsAfter: null })} placeholder="Exact name" value={skillName ?? ""} /></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="artifact-kind">Artifact kind</label><select className="form-select" id="artifact-kind" onChange={(event) => update({ artifactKind: event.target.value, artifactsAfter: null })} value={artifactKind ?? ""}><option value="">All kinds</option>{ARTIFACT_KINDS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="source-kind">Source kind</label><select className="form-select" id="source-kind" onChange={(event) => update({ sourceKind: event.target.value, artifactsAfter: null })} value={artifactSourceKind ?? ""}><option value="">All sources</option>{ARTIFACT_SOURCE_KINDS.map(({ label, value }) => <option key={value} value={value}>{label}</option>)}</select></div>
            <div className="col-12 col-lg-3"><label className="form-label" htmlFor="artifact-labels">Labels</label><input className="form-control" id="artifact-labels" onChange={(event) => update({ labels: event.target.value, artifactsAfter: null })} placeholder="Comma separated" value={searchParams.get("labels") ?? ""} /></div>
          </div>
        </form>
        <ProjectKnowledgeView
          artifact={artifact.data?.projectArtifact ?? null}
          asset={asset.data?.projectSkillAsset ?? null}
          catalog={catalog.data?.projectKnowledge ?? null}
          direction={direction}
          errorMessage={errors.map((error) => error.message).join("; ") || null}
          hrefForArtifact={(artifactId) => href({ artifact: artifactId, skill: null, asset: null, relationsAfter: null })}
          hrefForAsset={(path) => href({ asset: path })}
          hrefForSkill={(name) => href({ skill: name, asset: null, artifact: null, relationsAfter: null })}
          loading={catalog.isPending}
          onDirection={(value) => update({ direction: value, relationsAfter: null })}
          onNextArtifacts={(cursor) => update({ artifactsAfter: cursor })}
          onNextRelations={(cursor) => update({ relationsAfter: cursor })}
          onNextSkills={(cursor) => update({ skillsAfter: cursor })}
          onRelation={(value) => update({ relation: value, relationsAfter: null })}
          onRetry={retry}
          refreshing={[catalog, skill, asset, artifact].some((query) => query.isFetching && query.data !== undefined)}
          relation={relation}
          skill={skill.data?.projectSkill ?? null}
        />
      </div></div>
    </>
  );
}
