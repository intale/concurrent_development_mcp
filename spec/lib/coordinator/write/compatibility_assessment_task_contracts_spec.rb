# frozen_string_literal: true

RSpec.describe "compatibility assessment Task contracts" do
  include Dry::Monads[:result]

  let(:preparer) { Coordinator::Write::Operations::PrepareSubmitCompatibilityAssessment.new }
  let(:command) { preparer.call(VerificationEvidenceExamples.raw_input).value! }
  let(:command_digest) { Coordinator::Write::CommandInputDigest.new }

  it "prepares the strict public input as one named command and rejects cross-field failures" do
    expect(command).to be_a(Coordinator::Write::Commands::SubmitCompatibilityAssessment)
    expect(command.assessment.findings).to eq([])

    invalid = VerificationEvidenceExamples.raw_input(conclusion: "failed", findings: [])
    result = preparer.call(invalid)

    expect(result.failure.to_h).to include(
      code: :invalid_input,
      details: include(:assessment)
    )
  end

  it "separates command replay identity from canonical assessment deduplication identity" do
    assessment_digest = Coordinator::Write::CompatibilityAssessments::AssessmentInputDigest.new
    changed_envelope = command.new(
      command_id: "cmd-another-envelope",
      actor: command.actor.new(id: "agent-other"),
      claim: command.claim.new(
        claim_id: "07919191-9191-7191-8191-919191919191",
        fencing_token: 2
      )
    )

    expect(command_digest.call(changed_envelope)).not_to eq(command_digest.call(command))
    expect(assessment_digest.call(changed_envelope)).to eq(assessment_digest.call(command))
  end

  it "round-trips the persisted Task command document into the exact typed command" do
    submitted = Coordinator::Write::Events::CoordinationTaskSubmittedV2.new(
      task_id: "0198e03a-d112-7000-8000-000000000001",
      tool_name: "compatibility_assessment_submit",
      command_id: command.command_id,
      command_input: command_digest.document(command),
      submitted_at: "2026-08-24T08:00:00.000000Z",
      ttl_ms: nil,
      poll_interval_ms: 500
    )
    reloaded = Coordinator::Write::EventSchemaRegistry.new.load(
      type: "CoordinationTaskSubmitted",
      schema_version: 2,
      data: JSON.parse(JSON.generate(submitted.to_h))
    )

    expect(Coordinator::Write::Tasks::TargetCommandBuilder.new.call(reloaded.command_input)).to eq(command)
  end

  it "maps every evidence denial into a strict persisted Task result" do
    examples = [
      [ :verification_obligation_policy_stale, { obligation_id: "obl-1" }, "stale_context" ],
      [ :verification_obligation_unclaimed, { obligation_id: "obl-1" }, "conflict" ],
      [
        :verification_obligation_claim_stale,
        {
          obligation_id: "obl-1",
          current_claim_id: "01919191-9191-7191-8191-919191919191",
          current_fencing_token: 2
        },
        "conflict"
      ],
      [
        :verification_obligation_claim_not_owned,
        { obligation_id: "obl-1", claimant_id: "agent-blue" },
        "conflict"
      ],
      [
        :verification_obligation_claim_expired,
        { obligation_id: "obl-1", expires_at: "2026-08-24T08:00:00.000000Z" },
        "conflict"
      ],
      [
        :verification_obligation_binding_stale,
        { obligation_id: "obl-1", current_validity_input_digest: "sha256:#{"a" * 64}" },
        "stale_context"
      ],
      [
        :verification_evidence_kind_not_required,
        { obligation_id: "obl-1", evidence_kind: "security_review" },
        "denied"
      ],
      [
        :verification_evidence_already_submitted,
        { obligation_id: "obl-1", assessment_input_digest: "sha256:#{"b" * 64}" },
        "conflict"
      ],
      [
        :verification_evidence_limit_reached,
        { obligation_id: "obl-1", maximum_count: 32 },
        "conflict"
      ],
      [
        :verification_obligation_terminal,
        { obligation_id: "obl-1", status: "satisfied" },
        "conflict"
      ]
    ]
    mapper = Coordinator::Write::Tasks::ToolResultMapper.new

    examples.each do |code, details, status|
      result = mapper.call(
        Failure(
          Coordinator::Write::OutcomeError.new(
            code:,
            message: "assessment denied",
            details:
          )
        ),
        command_id: "cmd-assessment",
        tool_name: "compatibility_assessment_submit"
      )

      expect(result).to have_attributes(is_error: true)
      expect(result.structured_content).to have_attributes(status:)
      expect(result.structured_content.data.code).to eq(code.to_s)
    end
  end
end
