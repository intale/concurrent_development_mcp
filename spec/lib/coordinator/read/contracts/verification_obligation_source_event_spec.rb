# frozen_string_literal: true

RSpec.describe Coordinator::Read::Contracts::VerificationObligationSourceEvent do
  subject(:contract) { described_class.new }

  let(:input) do
    {
      event_type: "VerificationObligationCreated", schema_version: 2,
      stream_context: "DevelopmentIntegration", stream_name: "VerificationObligation",
      stream_id: SecureRandom.uuid_v7, stream_revision: 0, global_position: 1,
      command_id: SecureRandom.uuid_v7, actor_kind: "system",
      actor_id: "candidate-impact-obligation-policy", recorded_by: "coordinator",
      policy_version: "candidate-compatibility-obligation/v1"
    }
  end

  it "accepts native creation and preserves distinct current membership facts" do
    expect(contract.call(input)).to be_success
    membership = input.merge(event_type: "VerificationObligationAddedToChangeSet",
      schema_version: 1, stream_revision: 1)
    expect(contract.call(membership)).to be_success
    expect(contract.call(membership.merge(schema_version: 2)).errors.to_h).to have_key(:schema_version)
  end

  it "rejects all seven superseded verification event schemas" do
    %w[VerificationObligationCreated VerificationObligationClaimed VerificationEvidenceSubmitted
       VerificationObligationSatisfied VerificationObligationFailed VerificationObligationWaived
       VerificationObligationInvalidated].each do |event_type|
      expect(contract.call(input.merge(event_type:, schema_version: 1)).errors.to_h).to have_key(:schema_version)
    end
  end

  it "requires the native outcome policy and attribution rather than an evidence producer" do
    outcome = input.merge(event_type: "VerificationObligationSatisfied", stream_revision: 7,
      actor_id: "verification-evidence-outcome", policy_version: "verification-obligation-outcome/v2")
    expect(contract.call(outcome)).to be_success
    expect(contract.call(outcome.merge(actor_kind: "agent",
      policy_version: "compatibility-assessment/v2"))).to be_failure
  end
end
