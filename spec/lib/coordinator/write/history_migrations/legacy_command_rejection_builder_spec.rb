# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::LegacyCommandRejectionBuilder, :event_store do
  subject(:builder) do
    described_class.new(entity_reference_resolver: resolver,
      target_event_reference_resolver: Coordinator::Container["history_migrations.legacy_target_event_reference_resolver"])
  end

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:allocator) { Coordinator::Write::HistoryMigrations::StreamIdentityAllocator.new(event_store:) }
  let(:resolver) do
    Coordinator::Write::HistoryMigrations::LegacyEntityReferenceResolver.new(event_store:, stream_identity_allocator: allocator)
  end
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:command_id) { SecureRandom.uuid_v7 }
  let(:source_skill_id) { "skill:v1:#{'a' * 64}" }
  let(:source_event) { persist_skill }
  let(:error) do
    { "code" => "skill_revision_conflict", "message" => "Skill revision changed",
     "details" => { "skill_id" => source_skill_id, "name" => "governance", "scope" => "project:spec",
                   "current_revision" => 4, "expected_revision" => 3 } }
  end

  it "preserves full typed rejection evidence and resolves the same Skill allocation as its history" do
    fact = build.value!
    allocation = allocator.call(migration_id:, source_config_name: "default", source_event:,
      target_stream_context: "AgentKnowledge", target_stream_name: "Skill", identity_role: "skill").value!

    expect(fact).to be_a(Coordinator::Write::Events::CommandRejectedV2)
    expect(fact).to have_attributes(command_id:, retryable: false)
    expect(fact.error).to have_attributes(code: "skill_revision_conflict", message: "Skill revision changed")
    expect(fact.error.details).to have_attributes(skill_id: allocation.target_stream.stream_id,
      name: "governance", scope: "project:spec", expected_revision: 3, current_revision: 4)
    expect(build.value!).to eq(fact)
  end

  it "fails explicitly when the referenced Skill is outside the frozen range" do
    result = build(upper_position: source_event.global_position - 1)

    expect(result).to be_failure
    expect(result.failure.code).to eq(:ambiguous_source_reference)
  end

  it "does not fabricate details for unrepresentable historical evidence" do
    result = build(error_document: { code: "skill_revision_conflict", message: "Conflict", details: { skill_id: source_skill_id } })

    expect(result).to be_failure
    expect(result.failure.code).to eq(:invalid_source_event)
  end

  it "retains already typed historical denial details instead of converting them to a reason string" do
    evidence = Coordinator::Write::Tasks::DomainErrorV1::ChangeSetError.new(
      code: "change_set_already_exists", message: "Already exists",
      details: Coordinator::Write::Tasks::DomainErrorV1::ChangeSetDetails.new(change_set_id: "source-change-set"))

    expect(build(error_document: evidence).value!.error).to eq(evidence)
  end

  private

  def build(error_document: error, upper_position: source_event.global_position)
    builder.call(migration_id:, source_config_name: "default", source_upper_position: upper_position,
      source_event:, command_id:, error: error_document, retryable: false)
  end

  def persist_skill
    payload = Coordinator::Write::Events::SkillRevisionPublishedV2.new(
      skill_id: source_skill_id, name: "governance", scope: "project:spec", revision: 1,
      description: "Historical Skill", instructions: "Keep facts", assets: [],
      content_digest: "sha256:#{'b' * 64}", published_at: "2026-08-01T00:00:00.000000Z")
    event_store.append(
      Coordinator::Write::StreamReference.new(context: "AgentKnowledge", stream_name: "Skill", stream_id: source_skill_id),
      [ PgEventstore::Event.new(id: SecureRandom.uuid_v7, type: payload.class.event_type,
        data: payload.to_h, metadata: { "schema_version" => 2 }, markers: [ "skill:#{source_skill_id}" ]) ]
    ).sole
  end
end
