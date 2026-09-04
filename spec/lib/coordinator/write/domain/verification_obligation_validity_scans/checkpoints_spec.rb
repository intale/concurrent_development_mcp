# frozen_string_literal: true

RSpec.describe "Verification obligation validity scan checkpoints" do
  let(:actor) { { kind: "system", id: "verification-obligation-validity-policy" } }
  let(:scan_id) { "018f0000-0000-7000-8000-000000000020" }
  let(:change_set_id) { "018f0000-0000-7000-8000-000000000021" }
  let(:partition_event) do
    CandidateObligationExamples.partition_reference.new(stream_revision: 2)
  end

  it "starts a bounded global-position scan and advances a full page" do
    start_command = Coordinator::Write::Commands::StartVerificationObligationValidityScan.new(
      command_id: "validity-scan",
      actor:,
      scan_id:,
      change_set_id:,
      superseding_partition_event: partition_event,
      source_global_position: 300,
      rule_version: "verification-obligation-validity/v1"
    )
    start = Coordinator::Write::Domain::VerificationObligationValidityScans::Start.new.call(
      state: Coordinator::Write::Domain::VerificationObligationValidityScans::State.initial,
      command: start_command
    ).value!.events.first
    checkpoint = reference("VerificationObligationValidityScanStarted", 0)
    state = running_state(checkpoint)
    progress_command = progress_command(checkpoint, last_position: 140, count: 50, has_more: true)
    progressed = Coordinator::Write::Domain::VerificationObligationValidityScans::Progress.new.call(
      state:,
      command: progress_command
    ).value!.events.sole

    expect(start).to have_attributes(from_position: 0, to_position: 300, page_size: 50)
    expect(progressed).to have_attributes(
      next_from_position: 141,
      page_number: 1,
      change_set_id:,
      page_size: 50
    )
  end

  it "completes an empty page without moving beyond its current cursor" do
    checkpoint = reference("VerificationObligationValidityScanStarted", 0)
    completed = Coordinator::Write::Domain::VerificationObligationValidityScans::Progress.new.call(
      state: running_state(checkpoint),
      command: progress_command(checkpoint, last_position: nil, count: 0, has_more: false)
    ).value!.events.sole

    expect(completed).to have_attributes(scan_id:)
  end

  def running_state(checkpoint)
    Coordinator::Write::Domain::VerificationObligationValidityScans::State.new(
      status: "running",
      scan_id:,
      change_set_id:,
      superseding_partition_event: partition_event,
      started_event: checkpoint,
      checkpoint_event: checkpoint,
      from_position: 0,
      to_position: 300,
      page_size: 50,
      page_count: 0,
      rule_version: "verification-obligation-validity/v1"
    )
  end

  def progress_command(checkpoint, last_position:, count:, has_more:)
    Coordinator::Write::Commands::ProgressVerificationObligationValidityScan.new(
      command_id: "validity-progress",
      actor:,
      scan_id:,
      change_set_id:,
      superseding_partition_event: partition_event,
      expected_checkpoint: checkpoint,
      previous_from_position: 0,
      last_processed_position: last_position,
      page_obligation_count: count,
      has_more:,
      page_size: 50,
      rule_version: "verification-obligation-validity/v1"
    )
  end

  def reference(type, revision)
    Coordinator::Write::EventReference.new(
      event_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
      type:,
      stream_context: "DevelopmentIntegration",
      stream_name: "VerificationObligationValidityScan",
      stream_id: scan_id,
      stream_revision: revision
    )
  end
end
