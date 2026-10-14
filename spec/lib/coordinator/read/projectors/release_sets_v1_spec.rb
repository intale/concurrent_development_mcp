# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::ReleaseSetsV1, :read_model, :event_store do
  subject(:projector) do
    described_class.new(preparation_loader:)
  end

  let(:repository) { Coordinator::Read::Repositories::ReleaseSets.new }
  let(:release_set_id) { "RS-projection" }
  let(:change_set_id) { "CS-release-projection" }
  let(:repository_ids) do
    %w[
      018f0f4d-4e45-7abc-8def-000000000411
      018f0f4d-4e45-7abc-8def-000000000412
    ]
  end
  let(:candidate_ids) { %w[CAN-release-1 CAN-release-2] }
  let(:correlation_id) { SecureRandom.uuid_v7 }
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:preparation_loader) { Coordinator::Read::ReleaseSets::PreparationLoader.new(event_store:) }

  it "serves lagging not-found content and converges idempotently without a freshness gate" do
    query = Coordinator::Read::Queries::ReleaseSetGet.new
    expect(query.call(release_set_id:).value!.status).to eq("not_found")

    projector.call([ persisted_prepared_event ])
    projector.call([ persisted_prepared_event ])

    observed = query.call(release_set_id:).value!
    expect(observed.status).to eq("ok")
    expect(observed.warnings).to include("This view may lag the authoritative event store.")
    expect(observed.data.release_set).to have_attributes(
      release_set_id:,
      change_set_id:,
      status: "prepared"
    )
    expect(observed.data.release_set.ordered_members.map(&:repository_id)).to eq(repository_ids)
    expect(Coordinator::Read::ReleaseSet.count).to eq(1)
  end

  it "keeps the older view available while integration and verification lag, then converges in stream order" do
    create_release_set

    expect(repository.fetch(release_set_id)).to have_attributes(
      status: "prepared",
      verification_status: "unverified",
      integrations: [],
      verifications: []
    )

    [ *integration_events, *verification_events ].each do |event|
      projector.call([ event ])
      projector.call([ event ])
    end

    observed = repository.fetch(release_set_id)
    expect(observed).to have_attributes(status: "verified", verification_status: "passed")
    expect(observed.integrations.map(&:repository_id)).to eq(repository_ids)
    expect(observed.verifications.map { _1.evidence.outcome }).to eq([ "passed" ])
    expect(observed.verifications.sole.integration_events).to eq(integration_record_events.map { event_reference(_1) })
  end

  it "serves verified content while activation completion lags and then converges idempotently" do
    create_release_set
    [ *integration_events, *verification_events ].each { projector.call([ _1 ]) }

    expect(repository.fetch(release_set_id)).to have_attributes(
      status: "verified",
      activation: nil,
      completion: nil
    )

    [ activation_event, outcome_event, completion_event ].each do |event|
      projector.call([ event ])
      projector.call([ event ])
    end

    observed = repository.fetch(release_set_id)
    expect(observed).to have_attributes(status: "completed")
    expect(observed.activation.activation_point.environment).to eq("production")
    expect(observed.completion).to have_attributes(outcome: "activated")
  end

  it "projects each external repository compensation into the terminal view" do
    create_release_set
    [
      *integration_events,
      compensation_request_event,
      compensation_integration_link_event,
      repository_compensation_event,
      compensated_outcome_event,
      compensated_completion_event
    ].each do |event|
      projector.call([ event ])
      projector.call([ event ])
    end

    observed = repository.fetch(release_set_id)
    evidence = observed.completion.compensation_evidence.sole
    expect(observed).to have_attributes(status: "completed")
    expect(observed.completion).to have_attributes(outcome: "compensated")
    expect(evidence).to have_attributes(
      repository_id: repository_ids.first,
      integration_event: event_reference(integration_record_events.first),
      action: "revert",
      external_reference: "reverts/projection/1",
      result_digest: digest("c"),
      run_id: "release-compensation-projection"
    )
    expect(evidence.producer).to have_attributes(name: "release-reverter", version: "1.0")
  end

  it "starts verification only from its explicit fact, not the projected integration collection" do
    create_release_set
    projector.call(integration_events)
    expect(repository.fetch(release_set_id).status).to eq("integrating")

    requested = projection_event(Coordinator::Write::Events::ProjectionNumbers::ReleaseSetVerificationRequestedV1.new(release_set_id:),
      revision: 8, position: 399, policy_version: "release-set-integration/v1", actor_kind: "system")
    2.times { projector.call([ requested ]) }

    expect(repository.fetch(release_set_id)).to have_attributes(status: "verifying", verification_status: "unverified")
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  it "reapplies preparation columns without erasing lifecycle columns absent from that batch" do
    completion = { "outcome" => "activated", "operator_note" => "retained" }
    record = create_release_set(status: "completed", verification_status: "passed", completion:)
    original = record.attributes.slice("status", "verification_status", "completion", "integrations", "verifications")

    projector.call([ persisted_prepared_event ])

    expect(record.reload.attributes.slice(*original.keys)).to eq(original)
    expect(record.release_digest).to eq(digest("1"))
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  it "preserves linked evidence and collection order when recording facts or individual links are redelivered" do
    create_release_set
    projector.call([ *integration_events, *verification_events ])
    record = Coordinator::Read::ReleaseSet.find(release_set_id)
    original = record.attributes.slice("integrations", "verifications")

    projector.call([ integration_record_events.first, verification_event ])
    projector.call([ verification_events.fetch(1) ])

    expect(record.reload.attributes.slice(*original.keys)).to eq(original)
    expect(record.verifications.sole.fetch("integration_events").length).to eq(2)
  end

  it "converges a complete compensation chunk without duplicate integrations, links or compensation evidence" do
    create_release_set
    events = [ *integration_events, compensation_request_event, compensation_integration_link_event,
      repository_compensation_event, compensated_outcome_event, compensated_completion_event ]
    2.times { projector.call(events) }

    record = Coordinator::Read::ReleaseSet.find(release_set_id)
    expect(record.integrations.length).to eq(2)
    expect(record.compensation_request.fetch("successful_integrations").length).to eq(1)
    expect(record.compensation_request.fetch("integration_link_events").length).to eq(1)
    expect(record.completion.fetch("compensation_evidence").length).to eq(1)
    expect(repository.fetch(release_set_id).completion.outcome).to eq("compensated")
  end

  it "folds a thousand independent integrations into grouped updates without per-event SQL" do
    rows = Array.new(1000) { |index| attributes_for(:coordinator_read_release_set, release_set_id: "RS-batch-#{index}") }
    Coordinator::Read::ReleaseSet.insert_all!(rows)
    prototype = integration_record_events.first
    events = rows.map.with_index do |row, index|
      payload = Coordinator::Write::Events::RepositoryIntegrationRecordedV2.new(
        **prototype.data.transform_keys(&:to_sym).merge(release_set_id: row.fetch(:release_set_id)))
      projection_event(payload, revision: 4, position: index + 2000,
        metadata: Coordinator::Write::Metadata::RepositoryIntegrationV2.new(
          **metadata_attributes("release-set-integration/v1"), integration_digest: digest("4"),
          observation_digest: digest("2"), release_digest: digest("1")))
    end
    statements = []
    ActiveSupport::Notifications.subscribed(->(*args) { statements << args.last.fetch(:sql) }, "sql.active_record") do
      projector.call(events)
    end

    expect(statements.count { _1.start_with?("UPDATE") }).to be_between(1, 2)
    expect(statements.count { _1.start_with?("SELECT") && _1.include?('FROM "release_sets"') }).to eq(1)
    expect(Coordinator::Read::ReleaseSet.where(status: "integrating").count).to eq(1000)
    projector.call(events)
    expect(Coordinator::Read::ReleaseSet.all.map { _1.integrations.length }.uniq).to eq([ 1 ])
    expect(Coordinator::Read::ProcessedProjectionEvent.count).to eq(0)
  end

  def create_release_set(**attributes)
    create(:coordinator_read_release_set, release_set_id:, change_set_id:, repository_ids:, **attributes)
  end

  def persisted_prepared_event
    @persisted_prepared_event ||= event_store.append(
      Coordinator::Write::StreamFactory.new.release_set(release_set_id), preparation_events
    ).last
  end

  def preparation_events
    @preparation_events ||= [
        Coordinator::Write::Events::ReleaseSetCreatedV1.new(release_set_id:, change_set_id:),
        *repository_ids.each_with_index.map do |repository_id, index|
          Coordinator::Write::Events::ReleaseSetMemberAddedV1.new(
            release_set_id:,
            member_position: index + 1,
            repository_id:,
            merge_snapshot_id: "MS-release-#{index + 1}",
            ordered_candidate_ids: [ candidate_ids.fetch(index) ],
            authorization_event: source_reference(
              "MergeAuthorizationGranted",
              "MergeAuthorization",
              SecureRandom.uuid_v7,
              0
            )
          )
        end,
        Coordinator::Write::Events::ReleaseSetPreparedV2.new(release_set_id:)
      ].each_with_index.map do |payload, index|
        metadata = if payload.is_a?(Coordinator::Write::Events::ReleaseSetPreparedV2)
                     Coordinator::Write::Metadata::ReleaseSetPreparedV2.new(
                       **metadata_attributes("release-set-preparation/v1"),
                       release_digest: digest("1")
                     )
        else
                     Coordinator::Write::EventMetadata.new(**metadata_attributes("release-set-preparation/v1"))
        end
        projection_event(
          payload,
          revision: index,
          position: 100 + index,
          metadata:
        )
      end
  end

  def prepared_event
    preparation_events.last
  end

  def integration_events
    @integration_events ||= repository_ids.each_with_index.flat_map do |repository_id, index|
      recorded = projection_event(
        Coordinator::Write::Events::RepositoryIntegrationRecordedV2.new(
          release_set_id:,
          change_set_id:,
          repository_id:,
          member_position: index + 1,
          attempt_id: "integration-attempt-#{index + 1}",
          attempt_number: 1,
          outcome: "integrated",
          failure: nil
        ),
        revision: 4 + (index * 2),
        position: 200 + (index * 100),
        metadata: Coordinator::Write::Metadata::RepositoryIntegrationV2.new(
          **metadata_attributes("release-set-integration/v1"),
          integration_digest: digest((index + 4).to_s),
          observation_digest: digest((index + 2).to_s),
          release_digest: digest("1")
        )
      )
      linked = projection_event(
        Coordinator::Write::Events::RepositoryIntegrationMergeLinkedV1.new(
          release_set_id:,
          repository_id:,
          merge_observation: source_reference("MergeObserved", "MergeSnapshot", "MS-release-#{index + 1}", 3)
        ),
        revision: 5 + (index * 2),
        position: 201 + (index * 100),
        policy_version: "release-set-integration/v1",
        caused_by: recorded
      )
      [ recorded, linked ]
    end
  end

  def integration_record_events
    integration_events.each_slice(2).map(&:first)
  end

  def verification_events
    @verification_events ||= begin
      recorded = projection_event(
        Coordinator::Write::Events::ReleaseSetVerificationRecordedV2.new(
          release_set_id:,
          change_set_id:,
          attempt_number: 1,
          evidence: Coordinator::Write::ReleaseSets::VerificationEvidenceV2.new(
            producer: producer("release-tests"),
            run_id: "release-verification-run",
            environment_digest: digest("6"),
            result_digest: digest("7"),
            outcome: "passed",
            findings: [],
            produced_at: "2026-08-30T12:03:00.000000Z"
          )
        ),
        revision: 8,
        position: 400,
        metadata: Coordinator::Write::Metadata::ReleaseSetVerificationV2.new(
          **metadata_attributes("release-set-verification/v1"),
          release_digest: digest("1"),
          verification_digest: digest("8")
        )
      )
      links = integration_record_events.each_with_index.map do |integration, index|
        projection_event(
          Coordinator::Write::Events::ReleaseSetIntegrationLinkedV1.new(
            release_set_id:,
            integration_event: event_reference(integration)
          ),
          revision: 9 + index,
          position: 401 + index,
          policy_version: "release-set-verification/v1",
          caused_by: index.zero? ? recorded : nil
        )
      end
      [ recorded, *links ]
    end
  end

  def verification_event
    verification_events.first
  end

  def activation_event
    @activation_event ||= projection_event(
      Coordinator::Write::Events::ReleaseSetActivatedV2.new(
        release_set_id:,
        change_set_id:,
        activation_point: Coordinator::Write::ReleaseSets::ActivationPointV2.new(
          kind: "deployment_manifest",
          environment: "production",
          external_reference: "deployment://release/projection",
          state_digest: digest("9"),
          producer: producer("deployment-controller"),
          run_id: "release-activation-run"
        )
      ),
      revision: 11,
      position: 500,
      metadata: Coordinator::Write::Metadata::ReleaseSetActivationV2.new(
        **metadata_attributes("release-set-activation/v1"),
        activation_digest: digest("a"),
        release_digest: digest("1"),
        verification_digest: digest("8")
      ),
      caused_by: verification_events.last
    )
  end

  def outcome_event
    @outcome_event ||= projection_event(
      Coordinator::Write::Events::ReleaseSetOutcomeRecordedV1.new(
        release_set_id:,
        outcome: "activated"
      ),
      revision: 12,
      position: 600,
      metadata: Coordinator::Write::Metadata::ReleaseSetOutcomeV1.new(
        **metadata_attributes("release-set-completion/v1", actor_kind: "system"),
        completion_digest: digest("b"),
        release_digest: digest("1"),
        rule_version: "release-set-completion/v1"
      ),
      caused_by: activation_event
    )
  end

  def completion_event
    @completion_event ||= projection_event(
      Coordinator::Write::Events::ReleaseSetCompletedV2.new(release_set_id:),
      revision: 13,
      position: 601,
      policy_version: "release-set-completion/v1",
      actor_kind: "system",
      caused_by: outcome_event
    )
  end

  def compensation_request_event
    @compensation_request_event ||= projection_event(
      Coordinator::Write::Events::ReleaseSetCompensationRequestedV2.new(
        release_set_id:,
        change_set_id:,
        reason: "A later repository integration failed",
        trigger_kind: "repository_integration_failed"
      ),
      revision: 8,
      position: 500,
      metadata: Coordinator::Write::Metadata::ReleaseSetCompensationV2.new(
        **metadata_attributes("release-set-compensation/v1", actor_kind: "system"),
        release_digest: digest("1"),
        rule_version: "release-set-compensation/v1"
      ),
      actor_kind: "system",
      caused_by: integration_events.last
    )
  end

  def compensation_integration_link_event
    @compensation_integration_link_event ||= projection_event(
      Coordinator::Write::Events::ReleaseSetSuccessfulIntegrationLinkedV1.new(
        release_set_id:,
        integration_event: event_reference(integration_record_events.first)
      ),
      revision: 9,
      position: 501,
      policy_version: "release-set-compensation/v1",
      actor_kind: "system",
      caused_by: compensation_request_event
    )
  end

  def repository_compensation_event
    @repository_compensation_event ||= projection_event(
      Coordinator::Write::Events::RepositoryCompensationRecordedV1.new(
        release_set_id:,
        repository_id: repository_ids.first,
        integration_event: event_reference(integration_record_events.first),
        action: "revert",
        external_reference: "reverts/projection/1"
      ),
      revision: 10,
      position: 502,
      metadata: Coordinator::Write::Metadata::RepositoryCompensationV1.new(
        **metadata_attributes("release-set-completion/v1"),
        result_digest: digest("c"),
        producer: producer("release-reverter"),
        run_id: "release-compensation-projection"
      ),
      caused_by: compensation_integration_link_event
    )
  end

  def compensated_outcome_event
    @compensated_outcome_event ||= projection_event(
      Coordinator::Write::Events::ReleaseSetOutcomeRecordedV1.new(
        release_set_id:,
        outcome: "compensated"
      ),
      revision: 11,
      position: 503,
      metadata: Coordinator::Write::Metadata::ReleaseSetOutcomeV1.new(
        **metadata_attributes("release-set-completion/v1"),
        completion_digest: digest("d"),
        release_digest: digest("1"),
        rule_version: "release-set-completion/v1"
      ),
      caused_by: repository_compensation_event
    )
  end

  def compensated_completion_event
    @compensated_completion_event ||= projection_event(
      Coordinator::Write::Events::ReleaseSetCompletedV2.new(release_set_id:),
      revision: 12,
      position: 504,
      policy_version: "release-set-completion/v1",
      caused_by: compensated_outcome_event
    )
  end

  def projection_event(payload, revision:, position:, policy_version: nil, actor_kind: "agent", metadata: nil, caused_by: nil)
    ProjectionEventFactory.build(
      payload:,
      stream: Coordinator::Write::StreamFactory.new.release_set(payload.release_set_id),
      stream_revision: revision,
      global_position: position,
      policy_version: policy_version || metadata.policy_version,
      actor_kind:,
      actor_id: actor_kind == "system" ? "release-set-lifecycle" : "release-agent",
      correlation_id: caused_by ? nil : correlation_id,
      caused_by:,
      metadata:
    )
  end

  def metadata_attributes(policy_version, actor_kind: "agent")
    {
      command_id: "cmd-release-set-projection",
      actor_kind:,
      actor_id: actor_kind == "system" ? "release-set-lifecycle" : "release-agent",
      recorded_by: "coordinator",
      policy_version:
    }
  end

  def source_reference(type, stream_name, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: SecureRandom.uuid_v7,
      type:,
      stream_context: "DevelopmentIntegration",
      stream_name:,
      stream_id:,
      stream_revision: revision
    )
  end

  def event_reference(event)
    Coordinator::Write::EventReference.new(
      event_id: event.id,
      type: event.type,
      stream_context: event.stream.context,
      stream_name: event.stream.stream_name,
      stream_id: event.stream.stream_id,
      stream_revision: event.stream_revision
    )
  end

  def producer(name)
    Coordinator::Write::ReleaseSets::EvidenceProducerV1.new(name:, version: "1.0")
  end

  def digest(character)
    "sha256:#{character * 64}"
  end
end
