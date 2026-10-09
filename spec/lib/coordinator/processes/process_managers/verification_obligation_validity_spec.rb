# frozen_string_literal: true

RSpec.describe Coordinator::Processes::ProcessManagers::VerificationObligationValidity, :event_store do
  subject(:process_manager) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  let(:schemas) { Coordinator::Write::EventSchemaRegistry.new }

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
      reason: "policy_partition_advanced"
    )
    expect(scan_events(corrected).map(&:type)).to contain_exactly(
      "VerificationObligationValidityScanStarted",
      "VerificationObligationValidityScanCompleted"
    )
    partition_event = corrected.fetch(:partition_event)
    start_step = process_step(
      source_event: partition_event,
      step_name: "start-validity-scan",
      subject_kind: "candidate-policy-partition",
      subject_id: partition_event.id
    )
    invalidation_step = process_step(
      source_event: started,
      step_name: "invalidate-obligation",
      subject_kind: "obligation-policy-pair",
      subject_id: "#{created.fetch(:event).id}:#{partition_event.id}"
    )
    progress_step = process_step(
      source_event: started,
      step_name: "progress-validity-scan",
      subject_kind: "verification-obligation-validity-scan",
      subject_id: started.stream.stream_id
    )
    expect(started.causation_id).to eq(start_step.id)
    expect(invalidated.causation_id).to eq(invalidation_step.id)
    expect(completed.causation_id).to eq(progress_step.id)
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
    expect(load(invalidated)).to have_attributes(
      obligation_id: created.fetch(:payload).obligation_id,
      reason: "policy_partition_advanced"
    )
    step = process_step(
      source_event: created.fetch(:event),
      step_name: "invalidate-obligation",
      subject_kind: "obligation-policy-pair",
      subject_id: "#{created.fetch(:event).id}:#{corrected.fetch(:partition_event).id}"
    )
    expect(invalidated.causation_id).to eq(step.id)
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
          DecisionAddedToPartition
          DecisionRemovedFromPartition
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
    completed_event = scan_event(corrected, "VerificationObligationValidityScanCompleted")
    completed = load(completed_event)

    expect(load(progressed)).to have_attributes(
      page_number: 1,
      next_from_position: be_positive,
      change_set_id: created.dig(:pair, :ids, :change_set_id),
      page_size: 50
    )
    expect(completed).to have_attributes(scan_id: completed_event.stream.stream_id)
    snapshot = Coordinator::Write::VerificationObligationValidityScans::ScanLoader.new(event_store:).call(
      completed_event.stream.stream_id
    )
    expect(snapshot.state).to have_attributes(status: "completed", page_count: 2)
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
    event_store.read_global_marked(
      Coordinator::Write::GlobalMarkedEventReadCriteria.new(
        stream_context: "DevelopmentIntegration",
        stream_name: "VerificationObligationValidityScan",
        event_types: [ "VerificationObligationValidityScanStarted" ],
        markers: [ "superseding-partition-event:#{corrected.fetch(:partition_event).id}" ],
        maximum_count: 1,
        direction: :asc
      )
    ).first&.stream&.stream_id
  end

  def scan_events(corrected)
    id = scan_id(corrected)
    return [] unless id

    event_store.read_grouped(
      streams.verification_obligation_validity_scan(id),
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
    ids = Coordinator::Shared::IdGenerator.new
    definition = created.fetch(:payload)
    common_metadata = {
      command_id: "seed-validity-page",
      actor_kind: "system",
      actor_id: "candidate-impact-obligation-policy",
      recorded_by: "coordinator",
      policy_version: "candidate-compatibility-obligation/v1"
    }
    clones = Array.new(count) do
      obligation_id = ids.uuid_v7
      events = [
        Coordinator::Write::Events::VerificationObligationCreatedV2.new(
          obligation_id:,
          kind: definition.kind,
          reasons: definition.reasons.map(&:kind),
          required_evidence: definition.required_evidence,
          enforcement: definition.enforcement
        ),
        Coordinator::Write::Events::VerificationObligationAddedToChangeSetV1.new(
          obligation_id:,
          change_set_id: definition.change_set_id
        ),
        Coordinator::Write::Events::VerificationObligationSourceCandidateAssignedV1.new(
          obligation_id:,
          candidate_id: definition.source_candidate.candidate_id
        ),
        Coordinator::Write::Events::VerificationObligationTargetCandidateAssignedV1.new(
          obligation_id:,
          candidate_id: definition.target_candidate.candidate_id
        )
      ]
      correlation_id = ids.uuid_v7
      parent = nil
      physical = events.map.with_index do |event, index|
        metadata = if index.zero?
          Coordinator::Write::Metadata::VerificationObligationV2.new(
            **common_metadata,
            policy: definition.policy,
            rule_version: definition.rule_version,
            validity_input_digest: definition.validity_input_digest
          )
        else
          Coordinator::Write::EventMetadata.new(**common_metadata)
        end
        built = factory.build!(
          event:,
          event_id: ids.uuid_v7,
          metadata:,
          markers: [
            "verification-obligation:#{obligation_id}",
            "change-set:#{definition.change_set_id}"
          ],
          caused_by: parent,
          correlation_id:
        )
        parent = built
        built
      end
      [ obligation_id, physical ]
    end
    event_store.multiple do
      clones.each do |obligation_id, events|
        event_store.append(streams.verification_obligation(obligation_id), events)
      end
    end
    clones.map(&:first)
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

  def process_step(source_event:, step_name:, subject_kind:, subject_id:)
    ProcessStepExamples.event(
      event_store:,
      source_event:,
      process_name: "verification-obligation-validity-policy",
      step_name:,
      subject_kind:,
      subject_id:
    )
  end
end
