# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::VerificationObligationValidity, :event_store do
  subject(:process_manager) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }
  let(:identities) { Coordinator::Write::VerificationObligationValidityScans::IdentityBuilder.new }

  it "scans prior obligation creations and converges redelivery on one invalidation" do
    created = CandidateObligationScenario.create_obligation(prefix: "validity-process-scan")
    corrected = correct_policy(created, "validity-process-scan")

    process_manager.call(corrected.fetch(:partition_event))
    started = scan_event(corrected, "VerificationObligationValidityScanStarted")
    process_manager.call(started)
    process_manager.call(corrected.fetch(:partition_event))
    process_manager.call(started)

    invalidated = invalidation_events(created).sole
    completed = scan_event(corrected, "VerificationObligationValidityScanCompleted")
    expect(load(invalidated)).to have_attributes(
      obligation_id: created.fetch(:payload).obligation_id,
      superseding_partition_event: reference(corrected.fetch(:partition_event)),
      previous_status: "open"
    )
    expect(scan_events(corrected).map(&:type)).to contain_exactly(
      "VerificationObligationValidityScanStarted",
      "VerificationObligationValidityScanCompleted"
    )
    expect(started.causation_id).to eq(corrected.fetch(:partition_event).id)
    expect([ invalidated, completed ].map(&:causation_id).uniq).to eq([ started.id ])
    expect(
      [ corrected.fetch(:partition_event), started, invalidated, completed ].map(&:correlation_id).uniq
    ).to eq([ corrected.fetch(:partition_event).correlation_id ])
  end

  it "repairs an obligation creation delivered after its policy partition advanced" do
    created = CandidateObligationScenario.create_obligation(prefix: "validity-process-repair")
    corrected = correct_policy(created, "validity-process-repair")

    process_manager.call(created.fetch(:event))
    process_manager.call(created.fetch(:event))

    invalidated = invalidation_events(created).sole
    expect(load(invalidated).superseding_partition_event)
      .to eq(reference(corrected.fetch(:partition_event)))
    expect(invalidated.causation_id).to eq(created.fetch(:event).id)
    expect(invalidated.correlation_id).to eq(created.fetch(:event).correlation_id)
    expect(scan_events(corrected)).to be_empty
  end

  it "publishes one unique registration on the shared process-manager set" do
    registration = Coordinator::Processes::Subscriptions::VerificationObligationValidity.new(
      handler: process_manager,
      pull_interval: 0.1
    )

    expect(registration.definition.identity.to_h).to eq(
      set_name: "coordinator-process-managers-v1",
      subscription_name: "verification-obligation-validity-v1"
    )
    expect(registration.definition.options).to eq(
      filter: {
        streams: [
          { context: "HumanGuidance", stream_name: "DecisionPartition" },
          { context: "DevelopmentIntegration", stream_name: "VerificationObligation" },
          { context: "DevelopmentIntegration", stream_name: "VerificationObligationValidityScan" }
        ],
        event_types: %w[
          DecisionPartitionAdvanced
          VerificationObligationCreated
          VerificationObligationValidityScanStarted
          VerificationObligationValidityScanProgressed
        ]
      }
    )
  end

  it "persists and resumes a 51-obligation scan across two bounded pages" do
    created = CandidateObligationScenario.create_obligation(prefix: "validity-process-pages")
    obligation_ids = [ created.fetch(:payload).obligation_id ] + seed_obligation_clones(created, count: 50)
    corrected = correct_policy(created, "validity-process-pages")

    process_manager.call(corrected.fetch(:partition_event))
    started = scan_event(corrected, "VerificationObligationValidityScanStarted")
    process_manager.call(started)
    progressed = scan_event(corrected, "VerificationObligationValidityScanProgressed")
    process_manager.call(progressed)
    completed = load(scan_event(corrected, "VerificationObligationValidityScanCompleted"))

    expect(load(progressed)).to have_attributes(
      page_number: 1,
      page_obligation_count: 50,
      total_obligation_count: 50
    )
    expect(completed).to have_attributes(
      page_count: 2,
      page_obligation_count: 1,
      total_obligation_count: 51
    )
    expect(obligation_ids.sum { invalidation_events_for(_1).length }).to eq(51)
  end

  private

  def correct_policy(created, prefix)
    CandidateObligationScenario.correct_policy(
      policy: created.fetch(:policy),
      prefix:,
      change_set_id: created.dig(:pair, :ids, :change_set_id)
    )
  end

  def scan_id(corrected)
    identities.scan(
      superseding_partition_event: reference(corrected.fetch(:partition_event)),
      rule_version: "verification-obligation-validity/v1"
    )
  end

  def scan_events(corrected)
    event_store.read_grouped(
      streams.verification_obligation_validity_scan(scan_id(corrected)),
      Coordinator::Write::EventQueries::VERIFICATION_OBLIGATION_VALIDITY_SCAN_STATE
    )
  end

  def scan_event(corrected, type)
    scan_events(corrected).find { _1.type == type }
  end

  def invalidation_events(created)
    invalidation_events_for(created.fetch(:payload).obligation_id)
  end

  def invalidation_events_for(obligation_id)
    event_store.read(
      streams.verification_obligation(obligation_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "VerificationObligationInvalidated" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def seed_obligation_clones(created, count:)
    factory = Coordinator::Write::EventFactory.new
    metadata = Coordinator::Write::EventMetadata.new(
      command_id: "seed-validity-page",
      actor_kind: "system",
      actor_id: "candidate-impact-obligation-policy",
      recorded_by: "coordinator",
      policy_version: "candidate-compatibility-obligation/v1"
    )
    Array.new(count) do |index|
      obligation_id = "verification-obligation-v1:validity-page-#{index}"
      payload = created.fetch(:payload).new(obligation_id:)
      physical = factory.build!(
        event: payload,
        event_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
        metadata:,
        markers: [
          "verification-obligation:#{obligation_id}",
          "change-set:#{payload.change_set_id}"
        ]
      )
      event_store.append(streams.verification_obligation(obligation_id), [ physical ])
      obligation_id
    end
  end

  def load(event)
    schemas.load(
      type: event.type,
      schema_version: event.metadata.fetch("schema_version"),
      data: event.data
    )
  end

  def reference(event)
    Coordinator::Processes::CandidateObligations::EventReferenceBuilder.new.call(event)
  end
end
