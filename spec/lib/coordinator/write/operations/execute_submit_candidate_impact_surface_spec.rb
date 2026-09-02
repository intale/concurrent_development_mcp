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
      surface_digest: command.surface.digest,
      evidence_revision: 1,
      evidence_status: "attributed_unverified"
    )
    expect(completion.emitted_events.map(&:type)).to eq([
      "CandidateImpactSurfaceDerived",
      "CandidateImpactSurfaceRegistered"
    ])
    surface = impact_events(input.fetch(:candidate_id)).sole
    registration = registry_events(candidate.fetch(:input).fetch(:change_set_id)).sole
    expect(surface.data).to include(
      "manifest_digest" => input.fetch(:manifest_digest),
      "build_context_digest" => input.fetch(:build_context_digest),
      "surface_digest" => command.surface.digest
    )
    expect(surface.causation_id).to eq(parent.id)
    expect(surface.correlation_id).to eq(parent.correlation_id)
    expect(surface.metadata).not_to have_key("correlation_id")
    expect(registration.data).to include(
      "candidate_id" => input.fetch(:candidate_id),
      "surface_event" => completion.data.surface_event.to_h.stringify_keys,
      "index_policy_version" => "candidate-impact-exact-index/v2"
    )
    expect(registration.markers.grep(/compound:candidate-impact-index/)).not_to be_empty
    expect(registration.causation_id).to eq(parent.id)
    expect(registration.correlation_id).to eq(parent.correlation_id)
    expect(completion.data.registration_event).to eq(completion.emitted_events.fetch(1))
    expect(command_events(input.fetch(:command_id)).map(&:type)).to eq([ "CommandCompleted" ])
  end

  it "IMP-01-REPLAY-01 replays exact canonical input and rejects changed reuse" do
    candidate = CandidateScenario.submit(prefix: "impact-replay")
    input = impact_input(candidate)
    original = operation.call(input)
    ids = impact_events(input.fetch(:candidate_id)).map(&:id) +
      registry_events(candidate.fetch(:input).fetch(:change_set_id)).map(&:id) +
      command_events(input.fetch(:command_id)).map(&:id)
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

    expect(replay).to be_success
    expect(replay.value!).to eq(original.value!)
    expect(changed.failure.code).to eq(:command_id_reused)
    expect(
      impact_events(input.fetch(:candidate_id)).map(&:id) +
        registry_events(candidate.fetch(:input).fetch(:change_set_id)).map(&:id) +
        command_events(input.fetch(:command_id)).map(&:id)
    ).to eq(ids)
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
    expect(impact_events(valid.fetch(:candidate_id))).to be_empty
    expect(registry_events(candidate.fetch(:input).fetch(:change_set_id))).to be_empty
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
    expect(impact_events(first.fetch(:candidate_id)).length).to eq(1)
    registrations = registry_events(candidate.fetch(:input).fetch(:change_set_id))
    expect(registrations.length).to eq(1)
    expect(registrations.sole.data.fetch("candidate_id")).to eq(first.fetch(:candidate_id))
    expect(
      [ first, second ].sum { command_events(_1.fetch(:command_id)).length }
    ).to eq(1)
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
      manifest_digest: manifest.data.fetch("manifest_digest"),
      build_context_digest: context&.data&.fetch("build_context_digest"),
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

  def impact_events(candidate_id)
    event_store.read(
      streams.candidate(candidate_id),
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
      Coordinator::Write::EventQueries::COMMAND_COMPLETION
    )
  end

  def registry_events(change_set_id)
    event_store.read(
      streams.candidate_impact_registry(change_set_id),
      Coordinator::Write::EventReadCriteria.new(
        event_types: [ "CandidateImpactSurfaceRegistered" ],
        maximum_count: 4,
        direction: :asc
      )
    )
  end
end
