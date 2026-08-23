# frozen_string_literal: true

RSpec.describe Coordinator::Read::Projectors::CandidatesV1, :event_store, :read_model do
  subject(:projector) { described_class.new }

  it "serves each observed evidence stage and preserves exact source tracing" do
    scenario = CandidateScenario.submit(prefix: "candidate-project")
    submitted, manifest, build_context = scenario.fetch(:events)

    projector.call(submitted)
    projector.call(submitted)
    available = repository.fetch("CAN-candidate-project")
    expect(available).to have_attributes(
      evidence_status: "attributed_unverified",
      manifest: nil,
      build_context: nil,
      submitted: have_attributes(
        global_position: submitted.global_position,
        causation_id: submitted.causation_id,
        correlation_id: submitted.correlation_id
      )
    )

    projector.call(manifest)
    projector.call(build_context)
    projector.call(build_context)
    projected = repository.fetch("CAN-candidate-project")
    expect(projected.manifest).to have_attributes(
      digest: projected.manifest_digest,
      collector: have_attributes(kind: "agent", id: "agent-a", collector_version: "git-evidence-v1"),
      evidence: have_attributes(
        event: have_attributes(event_id: manifest.id, stream_revision: 1),
        global_position: manifest.global_position,
        causation_id: manifest.causation_id,
        correlation_id: manifest.correlation_id
      )
    )
    expect(projected.build_context).to have_attributes(
      digest: projected.build_context_digest,
      evidence: have_attributes(
        event: have_attributes(event_id: build_context.id, stream_revision: 2),
        global_position: build_context.global_position
      )
    )
    expect(projected.to_h.keys & %i[fresh pending projection_status]).to be_empty
    expect(Coordinator::Read::Candidate.count).to eq(1)
    expect(processed_events.count).to eq(3)
  end

  it "rolls back its idempotency claim when manifest evidence precedes submission" do
    submitted, manifest = CandidateScenario.submit(
      prefix: "candidate-project-order",
      build_context: false
    ).fetch(:events)

    expect { projector.call(manifest) }.to raise_error(
      Coordinator::Read::ProjectionStateError,
      "CandidateSubmitted must be projected before its manifest"
    )
    expect(processed_events).to be_empty

    projector.call(submitted)
    projector.call(manifest)
    expect(repository.fetch("CAN-candidate-project-order").manifest).not_to be_nil
  end

  it "indexes changed paths, observed inputs, and attributed impact keys idempotently" do
    scenario = CandidateScenario.submit(prefix: "candidate-impact-project")
    CandidateScenario.submit_impact(
      scenario,
      surface: {
        produces: [ { impact_key: "contract:payments-api:v2", after: "available" } ],
        consumes: [ { impact_key: "runtime:ruby", value: "4.0" } ],
        may_affect: [ { impact_key: "framework:rails:callbacks" } ],
        assumes: [ { impact_key: "database:postgresql", predicate: ">= 17" } ]
      }
    )
    events = CandidateScenario.candidate_events("CAN-candidate-impact-project")

    events.each { projector.call(_1) }
    events.each { projector.call(_1) }

    record = Coordinator::Read::Candidate.find("CAN-candidate-impact-project")
    expect(record.impact_surface).to include(
      "surface_digest" => a_string_matching(Coordinator::Shared::Types::SHA256_DIGEST_PATTERN),
      "evidence_status" => "attributed_unverified"
    )
    expect(Coordinator::Read::CandidateChangedResource.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(Coordinator::Read::CandidateObservedInput.pluck(:path)).to eq([ "lib/candidate.rb" ])
    expect(
      Coordinator::Read::CandidateImpactKey.order(:direction).pluck(:direction, :impact_key)
    ).to contain_exactly(
      [ "produces", "contract:payments-api:v2" ],
      [ "consumes", "runtime:ruby" ],
      [ "may_affect", "framework:rails:callbacks" ],
      [ "assumes", "database:postgresql" ]
    )
    expect(processed_events.count).to eq(4)
  end

  def repository
    @repository ||= Coordinator::Read::Repositories::Candidates.new
  end

  def processed_events
    Coordinator::Read::ProcessedProjectionEvent.where(
      projection_name: "candidates",
      projection_version: 1
    )
  end
end
