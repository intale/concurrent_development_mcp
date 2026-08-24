# frozen_string_literal: true

RSpec.describe Coordinator::Write::Contracts::SubmitCompatibilityAssessment do
  subject(:contract) { described_class.new }

  it "accepts the frozen exact assessment input" do
    expect(contract.call(VerificationEvidenceExamples.raw_input)).to be_success
  end

  it "rejects unknown keys and malformed identities, digests, and timestamps" do
    input = VerificationEvidenceExamples.raw_input
    input[:unknown] = true
    input[:claim][:claim_id] = "claim-1"
    input[:binding][:source_candidate][:head_commit_oid] = "HEAD"
    input[:assessment][:result_digest] = "digest"
    input[:assessment][:produced_at] = "today"

    expect(contract.call(input)).to be_failure
  end

  it "requires a finding for failed, inconclusive, and not-applicable evidence" do
    %w[failed inconclusive not_applicable].each do |conclusion|
      result = contract.call(VerificationEvidenceExamples.raw_input(conclusion:, findings: []))

      expect(result.errors.to_h.dig(:assessment)).to include("findings must explain a non-passed conclusion")
    end
  end

  it "bounds the evidence findings" do
    finding = { code: "failure", severity: "error", summary: "failure" }
    input = VerificationEvidenceExamples.raw_input(conclusion: "failed")
    input[:assessment][:findings] = Array.new(33, finding)

    expect(contract.call(input).errors.to_h.dig(:assessment)).to include("findings must contain at most 32 entries")
  end
end
