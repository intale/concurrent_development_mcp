import assert from "node:assert/strict";
import test from "node:test";
import { skillAssetTarget } from "../src/knowledge/project-knowledge-view.js";

test("relative Markdown references resolve only to assets in the current Skill manifest", () => {
  const assets = new Map([
    ["references/design.md", "/projects/project:work/skills/example/assets/references/design.md"],
    ["references/with space.md", "/skills/018f0f4d-4e45-7abc-8def-000000000011/assets/references/with%20space.md"]
  ]);
  assert.equal(skillAssetTarget("./references/design.md#contracts", assets), `${assets.get("references/design.md")}#contracts`);
  assert.equal(skillAssetTarget("references/with%20space.md", assets), assets.get("references/with space.md"));
  for (const href of ["references/missing.md", "../../etc/passwd", "https://example.org/references/design.md", "javascript:alert(1)", "%broken"]) {
    assert.equal(skillAssetTarget(href, assets), null);
  }
});
