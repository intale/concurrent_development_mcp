# frozen_string_literal: true

RSpec.describe "verification evidence event schemas" do
  let(:registry) { Coordinator::Write::EventSchemaRegistry.new }

  it "round-trips evidence, satisfaction, and failure facts through the schema registry" do
    evidence_id = "05919191-9191-7191-8191-919191919191"
    decider = Coordinator::Write::Domain::VerificationEvidence::Submit.new

    failed_plan = decider.call(
      state: VerificationEvidenceExamples.state,
      command: VerificationEvidenceExamples.command(conclusion: "failed"),
      evidence_id:,
      assessment_input_digest: VerificationEvidenceExamples.digest("failed-assessment"),
      submitted_at: VerificationEvidenceExamples::SUBMITTED_AT
    ).value!

    partial = VerificationEvidenceExamples.observation(evidence_kind: "combined_tests")
    satisfied_plan = decider.call(
      state: VerificationEvidenceExamples.state(evidence: [ partial ]),
      command: VerificationEvidenceExamples.command(evidence_kind: "contract_compatibility_review"),
      evidence_id:,
      assessment_input_digest: VerificationEvidenceExamples.digest("passed-assessment"),
      submitted_at: VerificationEvidenceExamples::SUBMITTED_AT
    ).value!

    events = [ failed_plan.events.first, failed_plan.events.last, satisfied_plan.events.last ]
    events.each do |event|
      loaded = registry.load(
        type: event.class.event_type,
        schema_version: event.class.schema_version,
        data: event.to_h.transform_keys(&:to_s)
      )

      expect(loaded).to eq(event)
    end
  end
end
