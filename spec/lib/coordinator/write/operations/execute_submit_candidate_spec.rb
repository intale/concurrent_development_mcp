# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteSubmitCandidate, :event_store do
  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }
  subject(:operation) { described_class.new(event_store:) }

  it "atomically submits a Candidate whose authority is expressed only by Resource UUID leases" do
    reservation = setup_reservation
    result = operation.call(candidate_input(reservation, command_id: "cmd-candidate-v2", candidate_id: "CAN-V2"))

    expect(result).to be_success
    receipt = result.value!.data
    expect(receipt).to be_a(Coordinator::Write::CommandReceiptData::CandidateSubmission)
    submission = candidate_events("CAN-V2").first
    expect(submission).to have_attributes(type: "CandidateSubmitted", stream_revision: 0)
    expect(submission.metadata).to include("schema_version" => 2, "policy_version" => "coordinator-resource-lease/v2")
    expect(submission.data.fetch("lease_references").map { _1.fetch("resource_id") }).to eq(reservation.resource_ids)
    expect(submission.data.to_s).not_to include("resource_key_hash")
    expect(attempt_events.count { _1.type == "CandidateAttachedToAttempt" }).to eq(1)
  end

  it "leaves replay ownership to the registered Command lifecycle and keeps an existing Candidate immutable" do
    reservation = setup_reservation
    input = candidate_input(reservation, command_id: "cmd-candidate-replay", candidate_id: "CAN-REPLAY")

    expect(operation.call(input)).to be_success
    replay = operation.call(input)
    changed = operation.call(input.merge(head_commit_oid: "e" * 40))

    expect(replay.failure.code).to eq(:candidate_id_already_used)
    expect(changed.failure.code).to eq(:candidate_id_already_used)
    expect(candidate_events("CAN-REPLAY").count { _1.type == "CandidateSubmitted" }).to eq(1)
  end

  it "rejects a manifest path that is not covered by the current UUID lease set" do
    reservation = setup_reservation
    input = candidate_input(reservation, command_id: "cmd-candidate-escape", candidate_id: "CAN-ESCAPE")
    input[:change_manifest][:files].sole[:old_path] = "lib/unleased.rb"
    input[:change_manifest][:files].sole[:new_path] = "lib/unleased.rb"

    result = operation.call(input)

    expect(result.failure).to have_attributes(code: :actual_write_set_not_authorized)
    expect(result.failure.details.fetch(:resources)).to contain_exactly(path: "lib/unleased.rb")
    expect(candidate_events("CAN-ESCAPE")).to be_empty
  end

  it "serializes a release before submission so stale authority cannot produce a partial Candidate" do
    reservation = setup_reservation
    Coordinator::Write::Operations::ExecuteReleaseLeaseSet.new(event_store:).call(
      command_id: "cmd-release-before-candidate",
      actor: { kind: "agent", id: "agent-a" },
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      lease_set_id: reservation.receipt.lease_set_id,
      leases: ResourceLeaseOperationScenario.lease_inputs(reservation.receipt)
    ).value!

    result = operation.call(
      candidate_input(reservation, command_id: "cmd-candidate-after-release", candidate_id: "CAN-STALE")
    )

    expect(result.failure).to have_attributes(code: :lease_set_released)
    expect(candidate_events("CAN-STALE")).to be_empty
  end

  def setup_reservation
    ResourceLeaseOperationScenario.start_attempts(
      event_store:,
      attempts: [ [ "W-LSE-A", "A-LSE-A", "agent-a" ] ]
    )
    ResourceLeaseOperationScenario.reserve(
      event_store:,
      paths: [ { kind: "file", path: "lib/example.rb", base_blob_oid: "c" * 40 } ]
    )
  end

  def candidate_input(reservation, command_id:, candidate_id:)
    {
      command_id:,
      actor: { kind: "agent", id: "agent-a" },
      candidate_id:,
      change_set_id: "CS-LSE",
      work_item_id: "W-LSE-A",
      attempt_id: "A-LSE-A",
      repository_id: RepositoryScenario::DEFAULT_REPOSITORY_ID,
      target_branch: "main",
      base_commit_oid: "a" * 40,
      head_commit_oid: "d" * 40,
      checkpoint_kind: "final",
      lease_set_id: reservation.receipt.lease_set_id,
      leases: ResourceLeaseOperationScenario.lease_inputs(reservation.receipt),
      change_manifest: {
        collector_version: "git-evidence-v1",
        files: [
          {
            status: "modified",
            old_path: "lib/example.rb",
            new_path: "lib/example.rb",
            old_blob_oid: "c" * 40,
            new_blob_oid: "d" * 40,
            old_mode: "100644",
            new_mode: "100644"
          }
        ]
      }
    }
  end

  def candidate_events(candidate_id)
    event_store.read(
      streams.candidate(candidate_id),
      Coordinator::Write::EventQueries::CANDIDATE_FOR_MERGE_SNAPSHOT
    )
  end

  def attempt_events
    event_store.read(
      streams.attempt("A-LSE-A"),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateAttachedToAttempt" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end
end
