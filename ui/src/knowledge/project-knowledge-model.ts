import type {
  ArtifactRelationDirection,
  DevelopmentArtifactKind,
  DevelopmentArtifactRelationKind,
  DevelopmentArtifactSourceKind,
  ProjectArtifactQuery,
  ProjectKnowledgeQuery,
  ProjectSkillAssetQuery,
  ProjectSkillQuery
} from "../gql/graphql.js";

export const ARTIFACT_KINDS: ReadonlyArray<{
  readonly label: string;
  readonly value: DevelopmentArtifactKind;
}> = [
  { label: "Build manifests", value: "BUILD_MANIFEST" },
  { label: "Build plans", value: "BUILD_PLAN" },
  { label: "Contracts", value: "CONTRACT" },
  { label: "Decision logs", value: "DECISION_LOG" },
  { label: "Decision records", value: "DECISION_RECORD" },
  { label: "Documentation", value: "DOCUMENTATION" },
  { label: "Event models", value: "EVENT_MODEL" },
  { label: "External references", value: "EXTERNAL_REFERENCE" },
  { label: "Governance", value: "GOVERNANCE" },
  { label: "Implementation records", value: "IMPLEMENTATION_RECORD" },
  { label: "Import manifests", value: "IMPORT_MANIFEST" },
  { label: "Other", value: "OTHER" },
  { label: "Performance profiles", value: "PERFORMANCE_PROFILE" },
  { label: "Repository checkpoints", value: "REPOSITORY_CHECKPOINT" },
  { label: "Verification evidence", value: "VERIFICATION_EVIDENCE" },
  { label: "Web research", value: "WEB_RESEARCH" }
];

export const ARTIFACT_SOURCE_KINDS: ReadonlyArray<{
  readonly label: string;
  readonly value: DevelopmentArtifactSourceKind;
}> = [
  { label: "Downloaded document", value: "DOWNLOADED_DOCUMENT" },
  { label: "Generated", value: "GENERATED" },
  { label: "Git commit", value: "GIT_COMMIT" },
  { label: "Local file", value: "LOCAL_FILE" },
  { label: "Other", value: "OTHER" },
  { label: "Web page", value: "WEB_PAGE" },
  { label: "Web search", value: "WEB_SEARCH" }
];

export const ARTIFACT_RELATIONS: readonly DevelopmentArtifactRelationKind[] = [
  "CONTAINS",
  "DERIVED_FROM",
  "DOCUMENTS",
  "EVIDENCES",
  "PRODUCED_BY_IMPORT",
  "REFERENCES",
  "SUPERSEDES"
];

export const RELATION_DIRECTIONS: readonly ArtifactRelationDirection[] = [
  "BOTH",
  "INCOMING",
  "OUTGOING"
];

export type ProjectKnowledge = NonNullable<ProjectKnowledgeQuery["projectKnowledge"]>;
export type ProjectSkill = NonNullable<ProjectSkillQuery["projectSkill"]>;
export type ProjectSkillAsset = NonNullable<ProjectSkillAssetQuery["projectSkillAsset"]>;
export type ProjectArtifact = NonNullable<ProjectArtifactQuery["projectArtifact"]>;

export function preserveKnowledgeForProject(
  previousData: ProjectKnowledgeQuery | undefined,
  previousQueryKey: readonly unknown[] | undefined,
  repositoryId: string
): ProjectKnowledgeQuery | undefined {
  return previousQueryKey?.[1] === repositoryId ? previousData : undefined;
}

export function humanized(value: string): string {
  return value.toLowerCase().replaceAll("_", " ");
}
