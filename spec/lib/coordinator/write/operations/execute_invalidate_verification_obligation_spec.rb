# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteInvalidateVerificationObligation, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:builder) do
    Coordinator::Processes::VerificationObligationValidity::CommandBuilder.new(event_store:)
  end

  it "atomically invalidates an open obligation from an exact later policy partition" do
    created = CandidateObligationScenario.create_obligation(prefix: "invalidate-open")
    corrected = correct_policy(created, "invalidate-open")
    invocation = invalidation(created, corrected)

    result = described_class.new(event_store:).call(invocation)
    replay = described_class.new(event_store:).call(invocation)
    event = invalidation_events(created).sole
    process_step = invocation.caused_by_event

    expect(result).to be_success
    expect(replay.failure.code).to eq(:verification_obligation_already_invalidated)
    expect(event).to have_attributes(
      causation_id: process_step.id,
      correlation_id: corrected.fetch(:partition_event).correlation_id
    )
    expect(process_step).to have_attributes(
      type: "ProcessStepPlanned",
      causation_id: corrected.fetch(:partition_event).id,
      correlation_id: corrected.fetch(:partition_event).correlation_id
    )
    expect(event.markers).to include(
      "verification-obligation:#{created.fetch(:payload).obligation_id}",
      "verification-obligation-status:invalidated",
      "change-set:#{created.dig(:pair, :ids, :change_set_id)}",
      "command:#{invocation.command.command_id}"
    )
    expect(load(event)).to have_attributes(
      obligation_id: created.fetch(:payload).obligation_id,
      superseding_partition_event: CandidateObligationScenario.reference(
        corrected.fetch(:partition_event)
      ),
      reason: "policy_partition_advanced"
    )
    expect(event.metadata).to include(
      "invalidated_policy" => created.fetch(:payload).policy.to_h.deep_stringify_keys,
      "rule_version" => "verification-obligation-validity/v1"
    )
  end

  it "supersedes a waived status while preserving the waiver fact" do
    created = CandidateObligationScenario.create_obligation(prefix: "invalidate-waived")
    Coordinator::Write::Operations::ExecuteWaiveVerificationObligation.new(event_store:).call(
      CandidateObligationScenario.waiver_arguments(
        created:,
        command_id: "cmd-invalidate-waived-waiver"
      )
    ).value!
    corrected = correct_policy(created, "invalidate-waived")

    event = described_class.new(event_store:).call(invalidation(created, corrected)).value!
    history = lifecycle_events(created)

    expect(load(event)).to have_attributes(
      obligation_id: created.fetch(:payload).obligation_id,
      superseding_partition_event: CandidateObligationScenario.reference(
        corrected.fetch(:partition_event)
      ),
      reason: "policy_partition_advanced"
    )
    expect(history.map(&:type)).to eq(%w[
      VerificationObligationCreated
      VerificationObligationWaived
      VerificationObligationInvalidated
    ])
  end

  private

  def correct_policy(created, prefix)
    CandidateObligationScenario.correct_policy(
      policy: created.fetch(:policy),
      prefix:,
      change_set_id: created.dig(:pair, :ids, :change_set_id)
    )
  end

  def invalidation(created, corrected)
    source = corrected.fetch(:partition_event)
    builder.invalidation(
      obligation_event: created.fetch(:event),
      superseding_partition_event: CandidateObligationScenario.reference(source),
      caused_by_event: source,
      caused_by_reference: CandidateObligationScenario.reference(source)
    )
  end

  def invalidation_events(created)
    event_store.read(
      streams.verification_obligation(created.fetch(:payload).obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationInvalidated" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def lifecycle_events(created)
    event_store.read(
      streams.verification_obligation(created.fetch(:payload).obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: %w[
          VerificationObligationCreated
          VerificationObligationWaived
          VerificationObligationInvalidated
        ],
        maximum_count: 3,
        direction: :asc
      )
    )
  end

  def load(event)
    Coordinator::Write::EventSchemaRegistry.new.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end
end
