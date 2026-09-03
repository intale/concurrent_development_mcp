# frozen_string_literal: true

RSpec.describe "granular Skill event contracts" do
  let(:skill_id) { "018f0f4d-4e45-7abc-8def-000000000101" }
  let(:revision_id) { "018f0f4d-4e45-7abc-8def-000000000102" }
  let(:asset_id) { "018f0f4d-4e45-7abc-8def-000000000103" }

  it "keeps Skill registration and publication facts cohesive" do
    registered = Coordinator::Write::Events::SkillRegisteredV1.new(
      skill_id:,
      name: "review",
      scope: "project:alpha"
    )
    published = Coordinator::Write::Events::SkillRevisionPublishedV3.new(
      skill_id:,
      skill_revision_id: revision_id,
      revision: 1
    )

    expect(registered.to_h).to eq(
      skill_id:,
      name: "review",
      scope: "project:alpha"
    )
    expect(published.to_h).to eq(
      skill_id:,
      skill_revision_id: revision_id,
      revision: 1
    )
    expect(published.to_h.keys).not_to include(:created_at, :published_at, :description, :instructions, :assets)
  end

  it "keeps revision, asset relation, and asset facts separate" do
    revision = Coordinator::Write::Events::SkillRevisionCreatedV1.new(
      skill_revision_id: revision_id,
      skill_id:,
      revision: 1
    )
    description = Coordinator::Write::Events::SkillRevisionDescriptionDefinedV1.new(
      skill_revision_id: revision_id,
      description: "Review changes."
    )
    instructions = Coordinator::Write::Events::SkillRevisionInstructionsDefinedV1.new(
      skill_revision_id: revision_id,
      instructions: "Inspect the complete diff."
    )
    asset = Coordinator::Write::Events::SkillAssetCreatedV1.new(asset_id:)
    path = Coordinator::Write::Events::SkillAssetPathDefinedV1.new(asset_id:, path: "scripts/check.sh")
    content = Coordinator::Write::Events::SkillAssetContentDefinedV1.new(asset_id:, content: "#!/bin/sh\n")
    executable = Coordinator::Write::Events::SkillAssetExecutabilityDefinedV1.new(asset_id:, executable: true)
    added = Coordinator::Write::Events::SkillAssetAddedToRevisionV1.new(
      skill_revision_id: revision_id,
      skill_id:,
      revision: 1,
      asset_id:
    )

    expect(revision.to_h).to include(skill_revision_id: revision_id, skill_id:, revision: 1)
    expect(description.to_h).to eq(skill_revision_id: revision_id, description: "Review changes.")
    expect(instructions.to_h).to eq(skill_revision_id: revision_id, instructions: "Inspect the complete diff.")
    expect(asset.to_h).to eq(asset_id:)
    expect(path.to_h).to eq(asset_id:, path: "scripts/check.sh")
    expect(content.to_h).to eq(asset_id:, content: "#!/bin/sh\n")
    expect(executable.to_h).to eq(asset_id:, executable: true)
    expect(added.to_h).to eq(skill_revision_id: revision_id, skill_id:, revision: 1, asset_id:)
  end

  it "allows binary content to be represented by canonical Base64" do
    content = Coordinator::Write::Events::SkillAssetContentDefinedV1.new(
      asset_id:,
      content: "AP8Q"
    )

    expect(content.content).to eq("AP8Q")
  end
end
