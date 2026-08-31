import {
  ProjectArtifactDocument,
  ProjectKnowledgeDocument,
  ProjectSkillAssetDocument,
  ProjectSkillDocument
} from "../gql/graphql.js";
import type {
  ArtifactRelationDirection,
  DevelopmentArtifactKind,
  DevelopmentArtifactRelationKind,
  DevelopmentArtifactSourceKind,
  ProjectArtifactQuery,
  ProjectArtifactQueryVariables,
  ProjectKnowledgeQuery,
  ProjectKnowledgeQueryVariables,
  ProjectSkillAssetQuery,
  ProjectSkillAssetQueryVariables,
  ProjectSkillQuery,
  ProjectSkillQueryVariables
} from "../gql/graphql.js";
import { executeGraphql } from "../graphql-client.js";

export const KNOWLEDGE_PAGE_SIZE = 20;

export interface KnowledgeFilters {
  readonly artifactKind?: DevelopmentArtifactKind;
  readonly artifactLabels: readonly string[];
  readonly artifactSourceKind?: DevelopmentArtifactSourceKind;
  readonly skillName?: string;
}

export interface KnowledgeCursors {
  readonly artifactsAfter?: string;
  readonly skillsAfter?: string;
}

export interface ArtifactRelationFilters {
  readonly direction: ArtifactRelationDirection;
  readonly relation?: DevelopmentArtifactRelationKind;
  readonly relationsAfter?: string;
}

export function fetchProjectKnowledge(
  repositoryId: string,
  filters: KnowledgeFilters,
  cursors: KnowledgeCursors,
  signal?: AbortSignal
): Promise<ProjectKnowledgeQuery> {
  const variables: ProjectKnowledgeQueryVariables = {
    repositoryId,
    first: KNOWLEDGE_PAGE_SIZE,
    artifactLabels: filters.artifactLabels,
    ...(filters.artifactKind ? { artifactKind: filters.artifactKind } : {}),
    ...(filters.artifactSourceKind ? { artifactSourceKind: filters.artifactSourceKind } : {}),
    ...(filters.skillName ? { skillName: filters.skillName } : {}),
    ...cursors
  };

  return executeGraphql(ProjectKnowledgeDocument, variables, signal);
}

export function fetchProjectSkill(
  repositoryId: string,
  name: string,
  signal?: AbortSignal
): Promise<ProjectSkillQuery> {
  const variables: ProjectSkillQueryVariables = { repositoryId, name };
  return executeGraphql(ProjectSkillDocument, variables, signal);
}

export function fetchProjectSkillAsset(
  repositoryId: string,
  name: string,
  path: string,
  signal?: AbortSignal
): Promise<ProjectSkillAssetQuery> {
  const variables: ProjectSkillAssetQueryVariables = { repositoryId, name, path };
  return executeGraphql(ProjectSkillAssetDocument, variables, signal);
}

export function fetchProjectArtifact(
  repositoryId: string,
  artifactId: string,
  filters: ArtifactRelationFilters,
  signal?: AbortSignal
): Promise<ProjectArtifactQuery> {
  const variables: ProjectArtifactQueryVariables = {
    repositoryId,
    artifactId,
    first: KNOWLEDGE_PAGE_SIZE,
    direction: filters.direction,
    ...(filters.relation ? { relation: filters.relation } : {}),
    ...(filters.relationsAfter ? { relationsAfter: filters.relationsAfter } : {})
  };
  return executeGraphql(ProjectArtifactDocument, variables, signal);
}
