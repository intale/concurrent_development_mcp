# frozen_string_literal: true

RSpec.describe Coordinator::Write::HistoryMigrations::TargetPlanWaveSelector, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:migration_id) { SecureRandom.uuid_v7 }
  let(:source_event) do
    event_store.append(
      Coordinator::Write::StreamReference.new(
        context: "LegacyDevelopmentPlanning",
        stream_name: "Repository",
        stream_id: "repository:v1:#{'a' * 64}"
      ),
      [
        PgEventstore::Event.new(
          id: SecureRandom.uuid_v7,
          type: "RepositoryRegistered",
          data: source_payload.to_h,
          metadata: { "schema_version" => 1 },
          correlation_id: SecureRandom.uuid_v7
        )
      ]
    ).sole
  end
  let(:source_payload) do
    Coordinator::Write::Events::RepositoryRegisteredV1.new(
      repository_id: SecureRandom.uuid_v7,
      scope: "project:legacy",
      repository_key: "legacy-app",
      display_name: "Legacy app",
      paths: [ "/workspace/legacy" ],
      remotes: [ "https://example.test/legacy.git" ],
      registered_at: "2026-01-01T12:00:00.000000Z"
    )
  end
  let(:transformer) do
    Coordinator::Write::HistoryMigrations::RepositoryRegisteredV1Transformer.new(
      stream_identity_allocator:
        Coordinator::Write::HistoryMigrations::StreamIdentityAllocator.new(event_store:)
    )
  end
  let(:target_event_planner) do
    Coordinator::Write::HistoryMigrations::TargetEventPlanner.new(event_store:)
  end
  let(:target_plan_builder) do
    Coordinator::Write::HistoryMigrations::TargetPlanBuilder.new(
      process_step_planner: Coordinator::Processes::ProcessStepPlanner.new(event_store:),
      target_event_planner:
    )
  end
  let(:selector) { described_class.new(event_store:) }

  it "selects only facts assigned to the requested persisted dependency wave" do
    transformed = transformed_facts
    plans = target_plan_builder.call(
      migration_id:,
      source_event:,
      transformed_facts: transformed
    ).value!

    selected = (0..Coordinator::Shared::Types::HISTORY_MIGRATION_DEPENDENCY_WAVE_MAXIMUM)
      .to_h do |dependency_wave|
        result = selector.call(
          migration_id:,
          source_event:,
          transformed_facts: transformed,
          dependency_wave:
        )
        expect(result).to be_success
        [ dependency_wave, result.value!.map(&:step_name) ]
      end

    expected = plans.group_by(&:dependency_wave).transform_values { _1.map(&:transformation_step) }
    expect(selected).to eq((0..3).to_h { [ _1, expected.fetch(_1, []) ] })
  end

  it "resolves a complete persisted source plan without replanning its process steps" do
    transformed = transformed_facts
    created = target_plan_builder.call(
      migration_id:,
      source_event:,
      transformed_facts: transformed
    ).value!

    result = selector.find_complete(
      migration_id:,
      source_event:,
      transformed_facts: transformed
    )

    expect(result).to be_success
    expect(result.value!.map(&:target_event)).to eq(created.map(&:target_event))
    expect(result.value!.map(&:outcome).uniq).to contain_exactly("existing")
  end

  it "rejects a persisted plan that does not cover the complete transformation" do
    target_plan_builder.call(
      migration_id:,
      source_event:,
      transformed_facts: transformed_facts.first(1)
    ).value!

    result = selector.call(
      migration_id:,
      source_event:,
      transformed_facts: transformed_facts,
      dependency_wave: 0
    )

    expect(result).to be_failure
    expect(result.failure).to include(
      code: :ambiguous_source_reference,
      source_event_id: source_event.id
    )
  end

  def transformed_facts
    @transformed_facts ||= transformer.call(
      migration_id:,
      source_config_name: "default",
      source_upper_position: source_event.global_position,
      source_event:,
      source_payload:
    ).value!
  end
end
