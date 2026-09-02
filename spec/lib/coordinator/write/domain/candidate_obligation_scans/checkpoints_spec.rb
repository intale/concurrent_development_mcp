# frozen_string_literal: true

RSpec.describe "Candidate impact obligation scan checkpoints" do
  let(:timestamp) { "2026-08-23T20:30:00.000000Z" }
  let(:actor) { { kind: "system", id: "candidate-impact-obligation-policy" } }
  let(:policy) { CandidateObligationExamples.policy }
  let(:policy_head) { CandidateObligationExamples.decision_head }
  let(:partition_event) { CandidateObligationExamples.partition_reference }

  it "starts and advances a bounded 50-registration registry page" do
    start_command = Coordinator::Write::Commands::StartCandidateImpactRegistrySweep.new(
      command_id: "registry-scan",
      actor:,
      scan_id: "registry-scan",
      change_set_id: "CS-obligation",
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
      latest_registry_revision: 120,
      started_at: timestamp
    ).value!.events.sole
    started_reference = reference("CandidateImpactRegistrySweepStarted", "registry-scan", 0)
    state = Coordinator::Write::Domain::CandidateObligationScans::RegistrySweepState.new(
      status: "running",
      scan_id: "registry-scan",
      change_set_id: "CS-obligation",
      policy_partition_event: partition_event,
      policy_head:,
      started_event: started_reference,
      checkpoint_event: started_reference,
      from_revision: 0,
      to_revision: 120,
      page_size: 50,
      page_count: 0,
      total_registration_count: 0,
      rule_version: "candidate-impact-registry-sweep/v1",
      skip_reason: nil
    )
    progress_command = Coordinator::Write::Commands::ProgressCandidateImpactRegistrySweep.new(
      command_id: "registry-progress",
      actor:,
      scan_id: "registry-scan",
      change_set_id: "CS-obligation",
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
      command: progress_command,
      progressed_at: timestamp
    ).value!.events.sole

    expect(start).to have_attributes(from_revision: 0, to_revision: 120, page_size: 50)
    expect(progressed).to have_attributes(
      previous_checkpoint: started_reference,
      next_from_revision: 50,
      page_number: 1,
      page_registration_count: 50,
      total_registration_count: 50
    )
  end

  it "starts a marker-routed predecessor scan and completes its final page" do
    source_registration = reference("CandidateImpactSurfaceRegistered", "CS-obligation", 3)
    markers = [ "compound:candidate-impact-index:v2|8:route=in" ]
    start_command = Coordinator::Write::Commands::StartCandidateImpactPairScan.new(
      command_id: "pair-scan",
      actor:,
      scan_id: "pair-scan",
      change_set_id: "CS-obligation",
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
      markers:,
      started_at: timestamp
    ).value!.events.sole
    started_reference = reference("CandidateImpactPairScanStarted", "pair-scan", 0)
    state = Coordinator::Write::Domain::CandidateObligationScans::PairScanState.new(
      status: "running",
      scan_id: "pair-scan",
      change_set_id: "CS-obligation",
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
      total_registration_count: 0,
      index_policy_version: "candidate-impact-exact-index/v2",
      rule_version: "candidate-impact-pair-scan/v1",
      skip_reason: nil
    )
    progress_command = Coordinator::Write::Commands::ProgressCandidateImpactPairScan.new(
      command_id: "pair-progress",
      actor:,
      scan_id: "pair-scan",
      change_set_id: "CS-obligation",
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
      command: progress_command,
      progressed_at: timestamp
    ).value!.events.sole

    expect(start).to have_attributes(markers:, from_revision: 0, to_revision: 2)
    expect(completed).to have_attributes(
      previous_checkpoint: started_reference,
      final_from_revision: 3,
      page_count: 1,
      page_registration_count: 2,
      total_registration_count: 2
    )
  end

  def reference(type, stream_id, revision)
    Coordinator::Write::EventReference.new(
      event_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      type:,
      stream_context: "DevelopmentIntegration",
      stream_name: type.include?("RegistrySweep") ? "CandidateImpactRegistrySweep" :
        type.include?("PairScan") ? "CandidateImpactPairScan" : "CandidateImpactRegistry",
      stream_id:,
      stream_revision: revision
    )
  end
end
