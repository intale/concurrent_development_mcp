# frozen_string_literal: true

RSpec.describe Coordinator::Write::CandidateObligations::IdentityBuilder do
  subject(:builder) { described_class.new }

  let(:source) do
    CandidateObligationExamples.evidence(
      candidate_id: "CAN-source",
      registry_revision: 0,
      path: "Gemfile"
    )
  end
  let(:target) do
    CandidateObligationExamples.evidence(
      candidate_id: "CAN-target",
      registry_revision: 1,
      path: "app/models/order.rb"
    )
  end

  it "derives one stable versioned identity from ordered surfaces and the exact policy partition" do
    first = build(source:, target:)
    second = build(source:, target:)

    expect(first).to eq(second)
    expect(first.obligation_id).to eq(
      "candidate-compatibility-obligation-v1:#{first.digest.delete_prefix('sha256:')}"
    )
    expect(first.document).to have_attributes(
      schema: "candidate-compatibility-obligation-identity/v1",
      rule_version: CandidateObligationExamples::RULE_VERSION,
      source_surface: source.subject.surface_event,
      target_surface: target.subject.surface_event,
      policy_partition_event: CandidateObligationExamples.partition_reference,
      policy_head: CandidateObligationExamples.decision_head
    )
  end

  it "preserves direction in the obligation identity" do
    outgoing = build(source:, target:)
    incoming = build(source: target, target: source)

    expect(incoming.obligation_id).not_to eq(outgoing.obligation_id)
  end

  it "changes identity when the exact policy partition advances without changing its head" do
    current = build(source:, target:)
    advanced = builder.call(
      source:,
      target:,
      policy_partition_event: CandidateObligationExamples.partition_reference.new(
        event_id: Coordinator::Shared::IdGenerator.new.uuid_v7,
        stream_revision: 1
      ),
      policy_head: CandidateObligationExamples.decision_head,
      rule_version: CandidateObligationExamples::RULE_VERSION
    )

    expect(advanced.obligation_id).not_to eq(current.obligation_id)
  end

  def build(source:, target:)
    builder.call(
      source:,
      target:,
      policy_partition_event: CandidateObligationExamples.partition_reference,
      policy_head: CandidateObligationExamples.decision_head,
      rule_version: CandidateObligationExamples::RULE_VERSION
    )
  end
end
