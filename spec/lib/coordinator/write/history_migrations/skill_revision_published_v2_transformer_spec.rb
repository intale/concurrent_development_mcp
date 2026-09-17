# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::SkillRevisionPublishedV2Transformer, :event_store do
  let(:source_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:target_store) do
    Coordinator::Write::EventStore.new(client: PgEventstore.client(:migration_target))
  end
  let(:registry) { Coordinator::Container["history_migrations.transformer_registry"] }
  let(:planner) { Coordinator::Container["history_migrations.event_planning_dispatcher"] }
  let(:dispatcher) { Coordinator::Container["history_migrations.event_dispatcher"] }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:legacy_skill_id) { "skill:v1:#{'a' * 64}" }
  let(:source_stream) do
    Coordinator::Write::StreamReference.new(
      context: "AgentKnowledge",
      stream_name: "Skill",
      stream_id: legacy_skill_id
    )
  end
  let(:source_correlation_id) { SecureRandom.uuid_v7 }

  it "decomposes immutable Skill revisions and assets into UUIDv7 target lifecycles" do
    first = persist_revision(
      revision: 1,
      description: "Initial guidance",
      instructions: "# Initial\n\nFollow the first revision.\n",
      assets: [ text_asset, binary_asset ],
      content_digest: "sha256:#{'1' * 64}"
    )
    second = persist_revision(
      revision: 2,
      description: "Updated guidance",
      instructions: "# Updated\n\nFollow the second revision.\n",
      assets: [ updated_text_asset ],
      content_digest: "sha256:#{'2' * 64}"
    )
    upper_position = second.global_position

    [ first, second ].each do |event|
      expect(plan(event, upper_position:)).to be_success
    end

    first_facts = transform(first, upper_position:).value!
    second_facts = transform(second, upper_position:).value!
    first_registration = fact_for(first_facts, Coordinator::Write::Events::SkillRegisteredV1)
    first_publication = fact_for(first_facts, Coordinator::Write::Events::SkillRevisionPublishedV3)
    second_publication = fact_for(second_facts, Coordinator::Write::Events::SkillRevisionPublishedV3)

    expect(first_facts.map { _1.event.class }).to eq([
      Coordinator::Write::Events::SkillRegisteredV1,
      Coordinator::Write::Events::SkillRevisionCreatedV1,
      Coordinator::Write::Events::SkillRevisionDescriptionDefinedV1,
      Coordinator::Write::Events::SkillRevisionInstructionsDefinedV1,
      Coordinator::Write::Events::SkillAssetCreatedV1,
      Coordinator::Write::Events::SkillAssetPathDefinedV1,
      Coordinator::Write::Events::SkillAssetContentDefinedV1,
      Coordinator::Write::Events::SkillAssetExecutabilityDefinedV1,
      Coordinator::Write::Events::SkillAssetAddedToRevisionV1,
      Coordinator::Write::Events::SkillAssetCreatedV1,
      Coordinator::Write::Events::SkillAssetPathDefinedV1,
      Coordinator::Write::Events::SkillAssetContentDefinedV1,
      Coordinator::Write::Events::SkillAssetExecutabilityDefinedV1,
      Coordinator::Write::Events::SkillAssetAddedToRevisionV1,
      Coordinator::Write::Events::SkillRevisionPublishedV3
    ])
    expect(second_facts.map { _1.event.class }).not_to include(
      Coordinator::Write::Events::SkillRegisteredV1
    )
    expect(second_facts.length).to eq(9)

    target_skill_id = first_registration.target_stream.stream_id
    expect(target_skill_id).to match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    expect(first_publication.target_stream).to eq(first_registration.target_stream)
    expect(second_publication.target_stream).to eq(first_registration.target_stream)
    expect(first_publication.event.skill_id).to eq(target_skill_id)
    expect(second_publication.event.skill_id).to eq(target_skill_id)
    expect(second_publication.event.skill_revision_id).not_to eq(
      first_publication.event.skill_revision_id
    )

    all_facts = first_facts + second_facts
    expect(all_facts.map { _1.target_stream.stream_id }.uniq).to all(
      match(Coordinator::Shared::Types::UUID_V7_PATTERN)
    )
    expect(all_facts.flat_map(&:markers).join("\n")).not_to include(legacy_skill_id, "sha256:")
    expect(all_facts.flat_map { _1.event.to_h.keys }).not_to include(:published_at)
    expect(first_registration.metadata_extension).to have_attributes(
      marker_codec_version: "compound-marker-v2",
      policy_version: "skill-repository/v1"
    )

    instructions = fact_for(
      second_facts,
      Coordinator::Write::Events::SkillRevisionInstructionsDefinedV1
    )
    expect(instructions.metadata_extension).to have_attributes(
      encoding: "utf-8",
      media_type: "text/markdown",
      byte_size: second.data.fetch("instructions").b.bytesize,
      content_sha256: sha256(second.data.fetch("instructions"))
    )
    first_asset_content = facts_for(
      first_facts,
      Coordinator::Write::Events::SkillAssetContentDefinedV1
    )
    expect(first_asset_content.map(&:metadata_extension)).to contain_exactly(
      have_attributes(
        encoding: "utf-8",
        media_type: "text/markdown",
        byte_size: text_asset.byte_size,
        content_sha256: text_asset.content_sha256
      ),
      have_attributes(
        encoding: "binary",
        media_type: "application/octet-stream",
        byte_size: binary_asset.byte_size,
        content_sha256: binary_asset.content_sha256
      )
    )
    expect(first_publication.metadata_extension).to have_attributes(
      content_digest: "sha256:#{'1' * 64}"
    )

    first_result = dispatch(first, upper_position:)
    second_result = dispatch(second, upper_position:)
    expect(first_result).to be_success
    expect(second_result).to be_success
    expect(dispatch(first, upper_position:).value!.outcome).to eq("existing")
    expect(dispatch(second, upper_position:).value!.outcome).to eq("existing")

    skill_events = target_events(first_registration.target_stream, maximum_count: 3)
    expect(skill_events.map(&:type)).to eq(
      %w[SkillRegistered SkillRevisionPublished SkillRevisionPublished]
    )
    expect(skill_events.map(&:stream_revision)).to eq([ 0, 1, 2 ])
    expect(skill_events.drop(1).map { _1.metadata.fetch("content_digest") }).to eq(
      [ "sha256:#{'1' * 64}", "sha256:#{'2' * 64}" ]
    )
    expect((first_result.value!.events + second_result.value!.events).map(&:correlation_id).uniq).to contain_exactly(
      first_result.value!.events.first.correlation_id
    )

    projection = Coordinator::Write::Skills::PublicationProjectionBuilderV3.new(
      event_store: target_store
    ).call(skill_events.last)
    expect(projection).to be_success
    expect(projection.value!).to have_attributes(
      skill_id: target_skill_id,
      name: "migration-review",
      scope: "project:legacy",
      revision: 2,
      description: "Updated guidance",
      instructions: "# Updated\n\nFollow the second revision.\n",
      content_digest: "sha256:#{'2' * 64}"
    )
    expect(projection.value!.assets.map(&:path)).to eq([ "references/updated.md" ])
    expect(projection.value!.assets.sole.content.text).to eq("Updated reference\n")
  end

  it "fails closed when a later revision changes the source Skill identity" do
    persist_revision(
      revision: 1,
      description: "Initial guidance",
      instructions: "# Initial\n",
      assets: [],
      content_digest: "sha256:#{'3' * 64}"
    )
    conflicting = persist_revision(
      revision: 2,
      name: "different-name",
      description: "Conflicting guidance",
      instructions: "# Conflict\n",
      assets: [],
      content_digest: "sha256:#{'4' * 64}"
    )

    result = transform(conflicting, upper_position: conflicting.global_position)

    expect(result).to be_failure
    expect(result.failure).to have_attributes(
      code: :ambiguous_source_reference,
      event_type: "SkillRevisionPublished",
      schema_version: 2,
      source_event_id: conflicting.id
    )
    expect(result.failure.message).to include("source Skill root is absent or inconsistent")
  end

  private

  def persist_revision(
    revision:,
    description:,
    instructions:,
    assets:,
    content_digest:,
    name: "migration-review"
  )
    payload = Coordinator::Write::Events::SkillRevisionPublishedV2.new(
      skill_id: legacy_skill_id,
      name:,
      scope: "project:legacy",
      revision:,
      description:,
      instructions:,
      assets:,
      content_digest:,
      published_at: "2026-08-01T12:00:0#{revision}.000000Z"
    )
    source_store.append(
      source_stream,
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "SkillRevisionPublished",
          data: payload.to_h,
          metadata: {
            "schema_version" => 2,
            "actor_kind" => "agent",
            "actor_id" => "legacy-agent",
            "policy_version" => "skill-repository/v1"
          },
          markers: [ "skill:#{legacy_skill_id}" ],
          correlation_id: source_correlation_id
        )
      ],
      expected_revision: revision == 1 ? :no_event : revision - 2
    ).sole
  end

  def text_asset
    content = "Reference material\n"
    Coordinator::Write::Skills::AssetV2.new(
      path: "references/guide.md",
      executable: false,
      content: Coordinator::Write::Content::TextV1.new(
        encoding: "utf-8",
        media_type: "text/markdown",
        text: content,
        content_sha256: sha256(content),
        byte_size: content.b.bytesize
      )
    )
  end

  def updated_text_asset
    content = "Updated reference\n"
    Coordinator::Write::Skills::AssetV2.new(
      path: "references/updated.md",
      executable: false,
      content: Coordinator::Write::Content::TextV1.new(
        encoding: "utf-8",
        media_type: "text/markdown",
        text: content,
        content_sha256: sha256(content),
        byte_size: content.b.bytesize
      )
    )
  end

  def binary_asset
    bytes = "\x00\x01\x02".b
    Coordinator::Write::Skills::AssetV2.new(
      path: "assets/payload.bin",
      executable: true,
      content: Coordinator::Write::Content::BinaryV1.new(
        encoding: "binary",
        media_type: "application/octet-stream",
        base64: [ bytes ].pack("m0"),
        content_sha256: sha256(bytes),
        byte_size: bytes.bytesize
      )
    )
  end

  def sha256(value)
    "sha256:#{OpenSSL::Digest::SHA256.hexdigest(value.b)}"
  end

  def plan(event, upper_position:)
    planner.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: event
    )
  end

  def transform(event, upper_position:)
    registry.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: event
    )
  end

  def dispatch(event, upper_position:)
    HistoryMigrationWaveDispatch.call(
      dispatcher:,
      migration_id:,
      source_config_name: "default",
      source_upper_position: upper_position,
      source_event: event
    )
  end

  def fact_for(facts, type)
    facts.find { _1.event.is_a?(type) }
  end

  def facts_for(facts, type)
    facts.select { _1.event.is_a?(type) }
  end

  def target_events(stream, maximum_count:)
    target_store.read(
      stream,
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "SkillRegistered", "SkillRevisionPublished" ],
        maximum_count:,
        direction: :asc
      )
    )
  end
end
