import {
  ProjectArtifactDocument,
  ProjectArtifactRelationshipsDocument,
  ProjectArtifactsDocument,
  ProjectSkillAssetDocument,
  ProjectSkillDocument,
  ProjectSkillsDocument,
  SkillAssetDocument,
  SkillDocument,
  SkillsDocument
} from "../gql/graphql.js";
import type {
  ArtifactRelationDirection,
  DevelopmentArtifactKind,
  DevelopmentArtifactRelationKind,
  DevelopmentArtifactSourceKind,
  ProjectArtifactQuery,
  ProjectArtifactQueryVariables,
  ProjectArtifactRelationshipsQuery,
  ProjectArtifactRelationshipsQueryVariables,
  ProjectArtifactsQuery,
  ProjectArtifactsQueryVariables,
  ProjectSkillAssetQuery,
  ProjectSkillAssetQueryVariables,
  ProjectSkillQuery,
  ProjectSkillQueryVariables,
  ProjectSkillsQuery,
  ProjectSkillsQueryVariables,
  SkillAssetQuery,
  SkillAssetQueryVariables,
  SkillQuery,
  SkillQueryVariables,
  SkillsQuery,
  SkillsQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export interface ArtifactFilters {
  readonly kind?: DevelopmentArtifactKind;
  readonly labels: readonly string[];
  readonly sourceKind?: DevelopmentArtifactSourceKind;
}

export interface RelationshipFilters {
  readonly direction: ArtifactRelationDirection;
  readonly relation?: DevelopmentArtifactRelationKind;
}

export function fetchSkills(
  projectScope: string | undefined,
  name: string | undefined,
  after: string | null,
  signal: AbortSignal
): Promise<SkillsQuery> {
  const variables: SkillsQueryVariables = {
    first: 20,
    ...(projectScope ? { projectScope } : {}),
    ...(name ? { name } : {}),
    ...(after ? { after } : {})
  };
  return executeGraphql(SkillsDocument, variables, signal);
}

export function fetchSkill(skillId: string, signal: AbortSignal): Promise<SkillQuery> {
  const variables: SkillQueryVariables = { skillId };
  return executeGraphql(SkillDocument, variables, signal);
}

export function fetchSkillAsset(
  skillId: string,
  path: string,
  signal: AbortSignal
): Promise<SkillAssetQuery> {
  const variables: SkillAssetQueryVariables = { skillId, path };
  return executeGraphql(SkillAssetDocument, variables, signal);
}

export function fetchProjectSkills(
  projectRef: string,
  name: string | undefined,
  after: string | null,
  signal: AbortSignal
): Promise<ProjectSkillsQuery> {
  const variables: ProjectSkillsQueryVariables = { projectRef, first: 20, name, after };
  return executeGraphql(ProjectSkillsDocument, variables, signal);
}

export function fetchProjectSkill(
  projectRef: string,
  name: string,
  signal: AbortSignal
): Promise<ProjectSkillQuery> {
  const variables: ProjectSkillQueryVariables = { projectRef, name };
  return executeGraphql(ProjectSkillDocument, variables, signal);
}

export function fetchProjectSkillAsset(
  projectRef: string,
  name: string,
  path: string,
  signal: AbortSignal
): Promise<ProjectSkillAssetQuery> {
  const variables: ProjectSkillAssetQueryVariables = { projectRef, name, path };
  return executeGraphql(ProjectSkillAssetDocument, variables, signal);
}

export function fetchProjectArtifacts(
  projectRef: string,
  filters: ArtifactFilters,
  after: string | null,
  signal: AbortSignal
): Promise<ProjectArtifactsQuery> {
  const variables: ProjectArtifactsQueryVariables = {
    projectRef,
    first: 20,
    kind: filters.kind,
    labels: [...filters.labels],
    sourceKind: filters.sourceKind,
    after
  };
  return executeGraphql(ProjectArtifactsDocument, variables, signal);
}

export function fetchProjectArtifact(
  projectRef: string,
  artifactId: string,
  signal: AbortSignal
): Promise<ProjectArtifactQuery> {
  const variables: ProjectArtifactQueryVariables = { projectRef, artifactId };
  return executeGraphql(ProjectArtifactDocument, variables, signal);
}

export function fetchProjectArtifactRelationships(
  projectRef: string,
  artifactId: string,
  filters: RelationshipFilters,
  after: string | null,
  signal: AbortSignal
): Promise<ProjectArtifactRelationshipsQuery> {
  const variables: ProjectArtifactRelationshipsQueryVariables = {
    projectRef,
    artifactId,
    first: 20,
    direction: filters.direction,
    relation: filters.relation,
    after
  };
  return executeGraphql(ProjectArtifactRelationshipsDocument, variables, signal);
}
