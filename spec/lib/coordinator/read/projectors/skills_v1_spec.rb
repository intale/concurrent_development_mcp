# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::SkillsV1, :read_model, :event_store do
  subject(:projector) do
    described_class.new(
      projection_builder: Coordinator::Write::Skills::PublicationProjectionBuilderV3.new(event_store:)
    )
  end

  let(:repository) { Coordinator::Read::Repositories::Skills.new }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:identity) do
    Coordinator::Write::Skills::IdentityBuilder.new.call(name: "review", scope: "project:alpha")
  end

  it "projects concrete immutable revisions idempotently with exact source evidence" do
    first_event = publication_event(
      revision: 1,
      instructions: "Inspect the complete diff.",
      path: "scripts/check.sh",
      content: "#!/bin/sh\nexit 0\n"
    )
    second_event = publication_event(
      revision: 2,
      instructions: "Inspect behavior and contracts.",
      path: "fixtures/example.json",
      content: "{}"
    )

    projector.call(first_event)
    projector.call(first_event)
    available = repository.fetch(name: "review", scope: "project:alpha")
    expect(available).to have_attributes(revision: 1, instructions: "Inspect the complete diff.")

    projector.call(second_event)
    projector.call(second_event)

    current = repository.fetch(name: "review", scope: "project:alpha")
    historical = repository.fetch(name: "review", scope: "project:alpha", revision: 1)
    expect(current).to have_attributes(
      revision: 2,
      instructions: "Inspect behavior and contracts.",
      published: have_attributes(
        event: have_attributes(event_id: second_event.id, stream_revision: 2),
        global_position: second_event.global_position,
        causation_id: second_event.causation_id,
        correlation_id: second_event.correlation_id
      )
    )
    expect(current.assets.map(&:path)).to eq([ "fixtures/example.json" ])
    expect(historical).to be_nil
    expect(
      repository.fetch_asset(
        name: "review",
        scope: "project:alpha",
        path: "scripts/check.sh",
        revision: 1
      )
    ).to be_nil
    expect(Coordinator::Read::Skill.count).to eq(1)
    expect(Coordinator::Read::SkillRevision.count).to eq(1)
    expect(Coordinator::Read::SkillAsset.count).to eq(1)
    expect(processed_events.count).to eq(2)
    expect(current.to_h.keys & %i[fresh pending projection_status]).to be_empty
    [ Coordinator::Read::Skill, Coordinator::Read::SkillRevision, Coordinator::Read::SkillAsset ].each do |model|
      expect(model.sole.updated_at).to eq(second_event.created_at)
    end
  end

  it "builds the newer granular revision first and never regresses on delayed older delivery" do
    first_event = publication_event(
      revision: 1,
      instructions: "Inspect the complete diff.",
      path: "scripts/check.sh",
      content: "#!/bin/sh\nexit 0\n"
    )
    second_event = publication_event(
      revision: 2,
      instructions: "Newest.",
      path: "fixtures/example.json",
      content: "{}"
    )

    projector.call(second_event)
    projector.call(first_event)

    current = repository.fetch(name: "review", scope: "project:alpha")
    historical = repository.fetch(name: "review", scope: "project:alpha", revision: 1)
    expect(current).to have_attributes(revision: 2, instructions: "Newest.")
    expect(historical).to be_nil
    expect(processed_events.count).to eq(2)
    expect(Coordinator::Read::Skill.sole.updated_at).to eq(second_event.created_at)
  end

  it "preserves attributed historical policy evidence on a current granular publication" do
    event = publication_event(
      revision: 1,
      instructions: "Model cohesive facts.",
      path: "SKILL.md",
      content: "Observed source.\n",
      policy_version: "skill-repository/v1"
    )

    projector.call(event)

    expect(repository.fetch(name: "review", scope: "project:alpha")).to have_attributes(
      skill_id: identity.skill_id,
      instructions: "Model cohesive facts."
    )
    expect(repository.fetch(name: "review", scope: "project:alpha").published.metadata)
      .to include("policy_version" => "skill-repository/v1", "schema_version" => 3)
  end

  it "rejects a superseded schema before claiming or creating a projection" do
    event = publication_event(revision: 1, instructions: "Current.", path: "SKILL.md", content: "Current.")
    event.metadata = event.metadata.merge("schema_version" => 2)

    expect { projector.call(event) }.to raise_error(Coordinator::Read::InvalidProjectionSource)
    expect(Coordinator::Read::Skill.count).to eq(0)
    expect(processed_events.count).to eq(0)
    expect do
      Coordinator::Write::EventSchemaRegistry.new.load(type: "SkillRevisionPublished", schema_version: 2, data: {})
    end.to raise_error(Coordinator::Write::EventSchemaRegistry::UnknownSchema)
  end

  def publication_event(revision:, instructions:, path:, content:, policy_version: "skill-repository/v2")
    asset_input = {
      path:,
      executable: false,
      content: {
        encoding: "utf-8",
        media_type: "text/plain",
        text: content
      }
    }
    revision_content = Coordinator::Write::Skills::RevisionBuilder.new.call(
      identity:,
      description: "Review a change",
      instructions:,
      assets: [ asset_input ]
    ).value!
    skill_id = identity.skill_id
    revision_id = SecureRandom.uuid_v7
    asset_id = SecureRandom.uuid_v7
    metadata = Coordinator::Write::EventMetadata.new(
      command_id: "cmd-skill-#{revision}", actor_kind: "agent", actor_id: "agent-1",
      recorded_by: "coordinator", policy_version:
    )
    events = Coordinator::Write::Events
    if revision == 1
      append_facts(streams.skill(skill_id), [
        events::SkillRegisteredV1.new(skill_id:, name: identity.name, scope: identity.scope)
      ], metadata)
    end
    append_facts(streams.skill_revision(revision_id), [
      events::SkillRevisionCreatedV1.new(skill_revision_id: revision_id, skill_id:, revision:),
      events::SkillRevisionDescriptionDefinedV1.new(skill_revision_id: revision_id, description: revision_content.description),
      events::SkillRevisionInstructionsDefinedV1.new(skill_revision_id: revision_id, instructions:)
    ], metadata)
    append_facts(streams.skill_asset(asset_id), [
      events::SkillAssetCreatedV1.new(asset_id:),
      events::SkillAssetPathDefinedV1.new(asset_id:, path:),
      events::SkillAssetExecutabilityDefinedV1.new(asset_id:, executable: false)
    ], metadata)
    asset_content = revision_content.assets.sole.content
    append_facts(streams.skill_asset(asset_id), [
      events::SkillAssetContentDefinedV1.new(asset_id:, content:)
    ], Coordinator::Write::Metadata::ContentV1.new(
      **metadata.to_h, encoding: "utf-8", media_type: asset_content.media_type,
      content_sha256: asset_content.content_sha256, byte_size: asset_content.byte_size
    ))
    append_facts(streams.skill_revision(revision_id), [
      events::SkillAssetAddedToRevisionV1.new(skill_revision_id: revision_id, skill_id:, revision:, asset_id:)
    ], metadata)
    append_facts(streams.skill(skill_id), [
      events::SkillRevisionPublishedV3.new(skill_id:, skill_revision_id: revision_id, revision:)
    ], Coordinator::Write::Metadata::SkillPublicationV3.new(
      **metadata.to_h, content_digest: revision_content.content_digest
    )).sole
  end

  def append_facts(stream, payloads, metadata)
    factory = Coordinator::Write::EventFactory.new
    event_store.append(
      stream,
      payloads.map do |payload|
        factory.build!(event: payload, event_id: SecureRandom.uuid_v7, metadata:, markers: [])
      end
    )
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "skills",
      projection_version: 4
    )
  end
end
