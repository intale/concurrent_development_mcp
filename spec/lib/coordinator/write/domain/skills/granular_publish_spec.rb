# frozen_string_literal: true

RSpec.describe Coordinator::Write::Domain::Skills::GranularPublish do
  subject(:decider) { described_class.new }

  let(:skill_id) { "018f0f4d-4e45-7abc-8def-000000000201" }
  let(:revision_id) { "018f0f4d-4e45-7abc-8def-000000000202" }
  let(:asset_id) { "018f0f4d-4e45-7abc-8def-000000000203" }
  let(:skill_stream) do
    Coordinator::Write::StreamReference.new(
      context: "AgentKnowledge",
      stream_name: "Skill",
      stream_id: skill_id
    )
  end
  let(:revision_stream) do
    Coordinator::Write::StreamReference.new(
      context: "AgentKnowledge",
      stream_name: "SkillRevision",
      stream_id: revision_id
    )
  end
  let(:asset_stream) do
    Coordinator::Write::StreamReference.new(
      context: "AgentKnowledge",
      stream_name: "SkillAsset",
      stream_id: asset_id
    )
  end
  let(:identity) do
    Coordinator::Write::Skills::IdentityV1.new(
      skill_id:,
      name: "review",
      scope: "project:alpha"
    )
  end
  let(:content) do
    Coordinator::Write::Skills::RevisionBuilder.new.call(
      identity:,
      description: "Review changes.",
      instructions: "Inspect the complete diff.",
      assets: [
        {
          path: "scripts/check.sh",
          executable: true,
          content: {
            encoding: "utf-8",
            media_type: "text/x-shellscript",
            text: "#!/bin/sh\n"
          }
        }
      ]
    ).value!
  end
  let(:command) do
    Coordinator::Write::Commands::PublishSkillRevision.new(
      command_id: "cmd-granular-skill",
      actor: Coordinator::Write::Commands::Actor.new(kind: "agent", id: "agent-1"),
      skill_id:,
      name: identity.name,
      scope: identity.scope,
      expected_revision: 0,
      description: content.description,
      instructions: content.instructions,
      assets: content.assets,
      content_digest: content.content_digest
    )
  end

  it "emits only cohesive facts across the Skill, revision, and asset streams" do
    result = decider.call(
      state: Coordinator::Write::Skills::SkillStateV1.initial(skill_id:),
      command:,
      skill_stream:,
      revision_stream:,
      asset_streams: [ asset_stream ],
      revision_id:
    )

    expect(result).to be_success
    decision = result.value!
    expect(decision.outcome).to eq("published")
    writes = decision.event_plan.writes
    expect(writes.map(&:event).map(&:class)).to eq([
      Coordinator::Write::Events::SkillRegisteredV1,
      Coordinator::Write::Events::SkillRevisionCreatedV1,
      Coordinator::Write::Events::SkillRevisionDescriptionDefinedV1,
      Coordinator::Write::Events::SkillRevisionInstructionsDefinedV1,
      Coordinator::Write::Events::SkillAssetCreatedV1,
      Coordinator::Write::Events::SkillAssetPathDefinedV1,
      Coordinator::Write::Events::SkillAssetContentDefinedV1,
      Coordinator::Write::Events::SkillAssetExecutabilityDefinedV1,
      Coordinator::Write::Events::SkillAssetAddedToRevisionV1,
      Coordinator::Write::Events::SkillRevisionPublishedV3
    ])
    expect(writes.map(&:stream).count { _1 == skill_stream }).to eq(2)
    expect(writes.map(&:stream).count { _1 == revision_stream }).to eq(4)
    expect(writes.map(&:stream).count { _1 == asset_stream }).to eq(4)
    expect(writes.find { _1.event.is_a?(Coordinator::Write::Events::SkillAssetContentDefinedV1) }.event.to_h)
      .to eq(asset_id:, content: "#!/bin/sh\n")
  end

  it "folds both text and binary content representations in asset state" do
    state = Coordinator::Write::Skills::AssetStateV1.reduce([
      Coordinator::Write::Events::SkillAssetCreatedV1.new(asset_id:),
      Coordinator::Write::Events::SkillAssetPathDefinedV1.new(asset_id:, path: "fixtures/raw.bin"),
      Coordinator::Write::Events::SkillAssetContentDefinedV1.new(asset_id:, content: "AP8Q"),
      Coordinator::Write::Events::SkillAssetExecutabilityDefinedV1.new(asset_id:, executable: false)
    ])

    expect(state).to have_attributes(
      asset_id:,
      path: "fixtures/raw.bin",
      content: "AP8Q",
      executable: false
    )
  end
end
