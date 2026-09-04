# frozen_string_literal: true

RSpec.describe "Candidate impact obligation scan checkpoints" do
  let(:actor) { { kind: "system", id: "candidate-impact-obligation-policy" } }
  let(:scan_id) { "018f0000-0000-7000-8000-000000000010" }
  let(:change_set_id) { "018f0000-0000-7000-8000-000000000011" }
  let(:policy) { CandidateObligationExamples.policy }
  let(:policy_head) { CandidateObligationExamples.decision_head }
  let(:partition_event) { CandidateObligationExamples.partition_reference }

  it "starts and advances a bounded 50-registration registry page" do
    start_command = Coordinator::Write::Commands::StartCandidateImpactRegistrySweep.new(
      command_id: "registry-scan",
      actor:,
      scan_id:,
      change_set_id:,
      policy_partition_event: partition_event,
      policy_head:,
      from_revision: 0,
      page_size: 50,
      rule_version: "candidate-impact-registry-sweep/v1"
    )
    start = Coordinator::Write::Domain::CandidateObligationScans::StartRegistrySweep.new.call(
      state: Coordinator::Write::Domain::CandidateObligationScans::RegistrySweepState.initial,
      command: start_command,
      policy:,
      latest_registry_revision: 120
    ).value!.events.first
    started_reference = reference("CandidateImpactRegistrySweepStarted", scan_id, 0)
    state = Coordinator::Write::Domain::CandidateObligationScans::RegistrySweepState.new(
      status: "running",
      scan_id:,
      change_set_id:,
      policy_partition_event: partition_event,
      policy_head:,
      started_event: started_reference,
      checkpoint_event: started_reference,
      from_revision: 0,
      to_revision: 120,
      page_size: 50,
      page_count: 0,
      rule_version: "candidate-impact-registry-sweep/v1",
      skip_reason: nil
    )
    progress_command = Coordinator::Write::Commands::ProgressCandidateImpactRegistrySweep.new(
      command_id: "registry-progress",
      actor:,
      scan_id:,
      change_set_id:,
      policy_partition_event: partition_event,
      policy_head:,
      expected_checkpoint: started_reference,
      previous_from_revision: 0,
      last_processed_revision: 49,
      page_registration_count: 50,
      has_more: true,
      page_size: 50,
      rule_version: "candidate-impact-registry-sweep/v1"
    )
    progressed = Coordinator::Write::Domain::CandidateObligationScans::ProgressRegistrySweep.new.call(
      state:,
      command: progress_command
    ).value!.events.sole

    expect(start).to have_attributes(from_revision: 0, to_revision: 120, page_size: 50)
    expect(progressed).to have_attributes(
      next_from_revision: 50,
      page_number: 1,
      change_set_id:,
      to_revision: 120,
      page_size: 50
    )
  end

  it "starts a marker-routed predecessor scan and completes its final page" do
    source_registration = reference("CandidateImpactSurfaceAssigned", "018f0000-0000-7000-8000-000000000012", 3)
    markers = [ "compound:candidate-impact-index:v2|8:route=in" ]
    start_command = Coordinator::Write::Commands::StartCandidateImpactPairScan.new(
      command_id: "pair-scan",
      actor:,
      scan_id:,
      change_set_id:,
      source_registration:,
      direction: "incoming",
      policy_partition_event: partition_event,
      policy_head:,
      from_revision: 0,
      to_revision: 2,
      page_size: 50,
      index_policy_version: "candidate-impact-exact-index/v2",
      rule_version: "candidate-impact-pair-scan/v1"
    )
    start = Coordinator::Write::Domain::CandidateObligationScans::StartPairScan.new.call(
      state: Coordinator::Write::Domain::CandidateObligationScans::PairScanState.initial,
      command: start_command,
      policy:,
      markers:
    ).value!.events.first
    started_reference = reference("CandidateImpactPairScanStarted", scan_id, 0)
    state = Coordinator::Write::Domain::CandidateObligationScans::PairScanState.new(
      status: "running",
      scan_id:,
      change_set_id:,
      source_registration:,
      direction: "incoming",
      policy_partition_event: partition_event,
      policy_head:,
      markers:,
      started_event: started_reference,
      checkpoint_event: started_reference,
      from_revision: 0,
      to_revision: 2,
      page_size: 50,
      page_count: 0,
      index_policy_version: "candidate-impact-exact-index/v2",
      rule_version: "candidate-impact-pair-scan/v1",
      skip_reason: nil
    )
    progress_command = Coordinator::Write::Commands::ProgressCandidateImpactPairScan.new(
      command_id: "pair-progress",
      actor:,
      scan_id:,
      change_set_id:,
      source_registration:,
      direction: "incoming",
      policy_partition_event: partition_event,
      policy_head:,
      expected_checkpoint: started_reference,
      previous_from_revision: 0,
      last_processed_revision: 2,
      page_registration_count: 2,
      has_more: false,
      page_size: 50,
      index_policy_version: "candidate-impact-exact-index/v2",
      rule_version: "candidate-impact-pair-scan/v1"
    )
    completed = Coordinator::Write::Domain::CandidateObligationScans::ProgressPairScan.new.call(
      state:,
      command: progress_command
    ).value!.events.sole

    expect(start).to have_attributes(markers:, from_revision: 0, to_revision: 2)
    expect(completed).to have_attributes(scan_id:)
  end

  def reference(type, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      type:,
      stream_context: "DevelopmentIntegration",
      stream_name: type.include?("RegistrySweep") ? "CandidateImpactRegistrySweep" :
        type.include?("PairScan") ? "CandidateImpactPairScan" : "Candidate",
      stream_id:,
      stream_revision: revision
    )
  end
end
