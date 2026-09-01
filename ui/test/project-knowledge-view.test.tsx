import assert from "node:assert/strict";
import test from "node:test";
import { renderToStaticMarkup } from "react-dom/server";
import { MemoryRouter } from "react-router-dom";
import type {
  ProjectArtifactQuery,
  ProjectKnowledgeQuery,
  ProjectSkillAssetQuery,
  ProjectSkillQuery
} from "../src/gql/graphql.js";
import { preserveKnowledgeForProject } from "../src/knowledge/project-knowledge-model.js";
import { ProjectKnowledgeView } from "../src/knowledge/project-knowledge-view.js";

const timestamp = "2026-08-31T12:00:00.000000Z";
const project = { id: "018f0f4d-4e45-7abc-8def-000000000081", name: "Knowledge", scope: "project:knowledge" };
const source = { kind: "LOCAL_FILE" as const, locator: "README.md", revision: "a".repeat(40), observedAt: timestamp, collector: "agent/v1" };
const artifactSummary = {
  id: `artifact:v1:${"a".repeat(64)}`,
  observationId: `artifact-observation:v1:${"a".repeat(64)}`,
  scope: project.scope,
  title: "Parent README",
  kind: "DOCUMENTATION" as const,
  labels: ["docs"],
  mediaType: "text/markdown",
  encoding: "utf-8",
  contentDigest: `sha256:${"a".repeat(64)}`,
  byteSize: 15,
  classificationRevision: 2,
  classificationReason: "Current documentation",
  relationshipCount: 1,
  capturedAt: timestamp,
  observedAt: timestamp,
  classifiedAt: timestamp,
  source
};
const catalog = {
  project,
  skills: {
    nodes: [{
      id: `skill:v1:${"1".repeat(64)}`,
      name: "event-modeling",
      scope: project.scope,
      revision: 2,
      description: "Model events",
      assetCount: 1,
      contentDigest: `sha256:${"1".repeat(64)}`,
      publishedAt: timestamp
    }],
    pageInfo: { endCursor: "next-skill", hasNextPage: true }
  },
  artifacts: {
    nodes: [artifactSummary],
    pageInfo: { endCursor: "next-artifact", hasNextPage: true }
  }
} satisfies NonNullable<ProjectKnowledgeQuery["projectKnowledge"]>;
const skill = {
  project,
  skill: {
    id: `skill:v1:${"1".repeat(64)}`,
    name: "event-modeling",
    scope: project.scope,
    revision: 2,
    description: "Model events",
    instructions: "Given facts, when a command runs, then emit events.",
    contentDigest: `sha256:${"1".repeat(64)}`,
    publishedAt: timestamp,
    assets: [{ path: "references/example.md", mediaType: "text/markdown", executable: false, contentDigest: `sha256:${"2".repeat(64)}`, byteSize: 42 }]
  }
} satisfies NonNullable<ProjectSkillQuery["projectSkill"]>;
const asset = {
  project,
  asset: { path: "references/example.md", revision: 2, encoding: "utf-8", mediaType: "text/markdown", executable: false, text: "Example content", base64: null, contentDigest: `sha256:${"2".repeat(64)}`, byteSize: 42 }
} satisfies NonNullable<ProjectSkillAssetQuery["projectSkillAsset"]>;
const artifact = {
  project,
  artifact: artifactSummary,
  content: { encoding: "utf-8", mediaType: "text/markdown", text: "# Parent README", base64: null, contentDigest: artifactSummary.contentDigest, byteSize: 15 },
  relationships: {
    nodes: [{
      id: `artifact-relation:v1:${"3".repeat(64)}`,
      direction: "OUTGOING" as const,
      relation: "CONTAINS" as const,
      displayRelation: "contains",
      peerKind: "artifact",
      peerId: `artifact:v1:${"b".repeat(64)}`,
      status: "active",
      targetStatus: "verified",
      targetName: null,
      targetScope: null,
      path: null,
      fragment: null,
      normalizedLocator: null,
      declaredAt: timestamp,
      peerArtifact: { ...artifactSummary, id: `artifact:v1:${"b".repeat(64)}`, observationId: `artifact-observation:v1:${"b".repeat(64)}`, title: "Child guide", source: { ...source, locator: "docs/guide.md" } }
    }],
    pageInfo: { endCursor: "next-relation", hasNextPage: true }
  }
} satisfies NonNullable<ProjectArtifactQuery["projectArtifact"]>;

const callbacks = {
  hrefForArtifact: (id: string) => `/knowledge?artifact=${id}`,
  hrefForAsset: (path: string) => `/knowledge?asset=${path}`,
  hrefForSkill: (name: string) => `/knowledge?skill=${name}`,
  onDirection: () => undefined,
  onNextArtifacts: () => undefined,
  onNextRelations: () => undefined,
  onNextSkills: () => undefined,
  onRelation: () => undefined,
  onRetry: () => undefined
};

function render(overrides: Partial<Parameters<typeof ProjectKnowledgeView>[0]> = {}) {
  return renderToStaticMarkup(<MemoryRouter><ProjectKnowledgeView artifact={artifact} asset={asset} catalog={catalog} direction="BOTH" errorMessage={null} loading={false} refreshing={false} relation={undefined} skill={skill} {...callbacks} {...overrides} /></MemoryRouter>);
}

test("shows current Skill content, assets, Artifact provenance, and active navigation", () => {
  const markup = render();
  assert.match(markup, /event-modeling/);
  assert.match(markup, /revision 2/);
  assert.match(markup, /references\/example.md/);
  assert.match(markup, /Example content/);
  assert.match(markup, /Parent README/);
  assert.match(markup, /docs\/guide.md/);
  assert.match(markup, /Next Skills page/);
  assert.match(markup, /Next Artifacts page/);
  assert.match(markup, /Next relationships page/);
  assert.match(markup, /Historical Skill revisions and superseded Artifact edges are intentionally absent/);
  assert.match(markup, /aria-label="Current Skills"/);
  assert.match(markup, /aria-label="Development Artifacts"/);
});

test("keeps latest available knowledge visible when a refresh fails", () => {
  const markup = render({ errorMessage: "Projection endpoint unavailable", refreshing: true });
  assert.match(markup, /last available knowledge view remains visible/);
  assert.match(markup, /Refreshing latest available knowledge facts/);
  assert.match(markup, /event-modeling/);
});

test("renders loading, unavailable, and retryable initial errors", () => {
  assert.match(render({ artifact: null, asset: null, catalog: null, skill: null, loading: true }), /Loading project knowledge/);
  assert.match(render({ artifact: null, asset: null, catalog: null, skill: null }), /not available in the latest projection/);
  assert.match(render({ artifact: null, asset: null, catalog: null, skill: null, errorMessage: "Network unavailable" }), /Retry/);
});

test("preserves an available catalog only for the same project", () => {
  const page: ProjectKnowledgeQuery = { projectKnowledge: catalog };
  assert.equal(preserveKnowledgeForProject(page, ["project-knowledge", project.id], project.id), page);
  assert.equal(preserveKnowledgeForProject(page, ["project-knowledge", "another-project"], project.id), undefined);
});
