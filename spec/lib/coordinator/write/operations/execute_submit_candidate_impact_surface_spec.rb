# frozen_string_literal: true

RSpec.describe Coordinator::Write::Operations::ExecuteSubmitCandidateImpactSurface, :event_store do
  subject(:operation) { described_class.new(event_store:) }

  let(:event_store) { Coordinator::Write::EventStore.new(client: PgEventstore.client) }
  let(:streams) { Coordinator::Write::StreamFactory.new }

  it "IMP-02-REGISTER-01 atomically records surface, registry, and completion with tracing" do
    candidate = CandidateScenario.submit(prefix: "impact-surface", build_context: true)
    input = impact_input(candidate)
    parent = candidate.fetch(:events).find { _1.type == "CandidateSubmitted" }
    command = Coordinator::Write::Operations::PrepareSubmitCandidateImpactSurface.new
      .call(input)
      .value!

    result = operation.call_command(command, caused_by: parent)

    expect(result).to be_success
    completion = result.value!
    expect(completion.data).to be_a(
      Coordinator::Write::CommandReceiptData::CandidateImpactSurface
    )
    expect(completion.data).to have_attributes(
      candidate_id: input.fetch(:candidate_id),
      surface_id: completion.data.surface_event.stream_id,
      surface_digest: command.surface.digest,
      evidence_revision: 1,
      evidence_status: "attributed_unverified"
    )
    expect(completion.emitted_events.map(&:type)).to eq([
      "CandidateImpactSurfaceDerived",
      "CandidateImpactSurfaceAssigned"
    ])
    assignment = assignment_events(input.fetch(:candidate_id)).sole
    surface = impact_events(assignment.data.fetch("surface_id")).sole
    expect(surface.data).to include(
      "surface_id" => assignment.data.fetch("surface_id"),
      "candidate_id" => input.fetch(:candidate_id),
      "evidence_revision" => 1
    )
    expect(surface.metadata).to include(
      "manifest_digest" => input.fetch(:manifest_digest),
      "build_context_digest" => input.fetch(:build_context_digest),
      "surface_digest" => command.surface.digest
    )
    expect(surface.causation_id).to eq(parent.id)
    expect(surface.correlation_id).to eq(parent.correlation_id)
    expect(surface.metadata).not_to have_key("correlation_id")
    expect(assignment.data).to eq(
      "candidate_id" => input.fetch(:candidate_id),
      "surface_id" => completion.data.surface_id
    )
    expect(assignment.markers.grep(/compound:candidate-impact-index/)).not_to be_empty
    expect(assignment.causation_id).to eq(parent.id)
    expect(assignment.correlation_id).to eq(parent.correlation_id)
    expect(completion.data.registration_event).to eq(completion.emitted_events.fetch(1))
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "IMP-01-REPLAY-01 leaves replay ownership to the registered Command lifecycle" do
    candidate = CandidateScenario.submit(prefix: "impact-replay")
    input = impact_input(candidate)
    expect(operation.call(input)).to be_success
    assignment = assignment_events(input.fetch(:candidate_id)).sole
    ids = impact_events(assignment.data.fetch("surface_id")).map(&:id) +
      assignment_events(input.fetch(:candidate_id)).map(&:id)
    reordered = input.merge(
      surface: input.fetch(:surface).merge(
        produces: input.dig(:surface, :produces).reverse
      )
    )

    replay = operation.call(reordered)
    changed = operation.call(
      input.merge(
        surface: input.fetch(:surface).merge(
          produces: [ { impact_key: "runtime:ruby", after: "3.4" } ]
        )
      )
    )

    expect(replay.failure.code).to eq(:candidate_impact_surface_already_recorded)
    expect(changed.failure.code).to eq(:candidate_impact_surface_already_recorded)
    expect(
      impact_events(assignment.data.fetch("surface_id")).map(&:id) +
        assignment_events(input.fetch(:candidate_id)).map(&:id)
    ).to eq(ids)
    expect(command_events(input.fetch(:command_id))).to be_empty
  end

  it "denies absent, identity-mismatched, and stale source evidence without target facts" do
    candidate = CandidateScenario.submit(prefix: "impact-denials")
    valid = impact_input(candidate)
    cases = [
      valid.merge(command_id: "cmd-impact-absent", candidate_id: "CAN-absent"),
      valid.merge(command_id: "cmd-impact-identity", repository_id: RepositoryScenario.repository_id("other")),
      valid.merge(
        command_id: "cmd-impact-evidence",
        manifest_digest: "sha256:#{"f" * 64}"
      )
    ]

    results = cases.map { operation.call(_1) }

    expect(results.map { _1.failure.code }).to eq([
      :candidate_not_found,
      :candidate_impact_identity_mismatch,
      :candidate_impact_source_evidence_mismatch
    ])
    expect(assignment_events(valid.fetch(:candidate_id))).to be_empty
    cases.each { expect(command_events(_1.fetch(:command_id))).to be_empty }
  end

  it "IMP-01-RACE-01 serializes competing initial surfaces to exactly one winner" do
    candidate = CandidateScenario.submit(prefix: "impact-race")
    first = impact_input(candidate)
    second = first.merge(
      command_id: "cmd-impact-race-other",
      surface: first.fetch(:surface).merge(
        produces: [ { impact_key: "runtime:ruby", before: "3.3", after: "4.0" } ]
      )
    )

    results = [ first, second ].map do |input|
      Thread.new { described_class.new(event_store:).call(input) }
    end.map(&:value)

    expect(results.count(&:success?)).to eq(1)
    expect(results.count(&:failure?)).to eq(1)
    expect(results.find(&:failure?).failure.code).to eq(
      :candidate_impact_surface_already_recorded
    )
    assignments = assignment_events(first.fetch(:candidate_id))
    expect(assignments.length).to eq(1)
    expect(impact_events(assignments.sole.data.fetch("surface_id")).length).to eq(1)
    expect(assignments.sole.data.fetch("candidate_id")).to eq(first.fetch(:candidate_id))
    expect([ first, second ].flat_map { command_events(_1.fetch(:command_id)) }).to be_empty
  end

  def impact_input(candidate)
    input = candidate.fetch(:input)
    manifest = candidate.fetch(:events).find { _1.type == "CandidateChangeManifestCaptured" }
    context = candidate.fetch(:events).find { _1.type == "CandidateBuildContextCaptured" }
    {
      command_id: "cmd-impact-#{input.fetch(:candidate_id)}",
      actor: { kind: "agent", id: "analyzer-7" },
      candidate_id: input.fetch(:candidate_id),
      repository_id: input.fetch(:repository_id),
      head_commit_oid: input.fetch(:head_commit_oid),
      manifest_digest: manifest.metadata.fetch("manifest_digest"),
      build_context_digest: context&.metadata&.fetch("build_context_digest"),
      analyzer_version: "impact-analyzer-v1",
      surface: {
        produces: [
          { impact_key: "runtime:ruby", before: "3.3", after: "4.0" },
          {
            impact_key: "dependency:rubygems:rails",
            before: "7.2",
            after: "8.0"
          }
        ],
        consumes: [],
        may_affect: [ { impact_key: "framework:rails:controller-lifecycle" } ],
        assumes: []
      }
    }.compact
  end

  def impact_events(surface_id)
    event_store.read(
      streams.candidate_impact_surface(surface_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceDerived" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end

  def command_events(command_id)
    event_store.read(
      streams.command(command_id),
      Coordinator::Write::EventQueries::COMMAND_HISTORY
    )
  end

  def assignment_events(candidate_id)
    event_store.read(
      streams.candidate(candidate_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceAssigned" ],
        maximum_count: 1,
        direction: :asc
      )
    )
  end
end
