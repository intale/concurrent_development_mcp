# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateCompatibilityObligationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::CandidateObligations::State))
        required(:command).value(Types.Instance(Commands::CreateCandidateCompatibilityObligation))
        required(:created_at).filled(:string)
      end

      rule(:plan, :state, :command, :created_at) do
        plan = values[:plan]
        state = values[:state]
        command = values[:command]
        event = plan.events.first
        policy = state.policy.evidence
        reasons = CandidateObligations::Matcher.new.call(source: state.source, target: state.target)
        valid = plan.writes.length == 1 &&
                plan.writes.first.stream == StreamFactory.new.verification_obligation(command.obligation_id) &&
                event.is_a?(Events::VerificationObligationCreatedV1) &&
                !state.existing && policy && !reasons.empty?
        unless valid
          key(:plan).failure("must contain one new exact VerificationObligation creation")
          next
        end

        validity = CandidateObligations::ValidityBuilder.new.call(
          source: state.source,
          target: state.target,
          reasons:,
          policy:,
          rule_version: command.rule_version
        )
        expected = Events::VerificationObligationCreatedV1.new(
          obligation_id: command.obligation_id,
          kind: "candidate_compatibility",
          status: "open",
          change_set_id: state.source.subject.change_set_id,
          source_candidate: state.source.subject,
          target_candidate: state.target.subject,
          reasons:,
          required_evidence: policy.required_evidence,
          enforcement: policy.enforcement,
          policy:,
          validity_input_digest: validity.digest,
          rule_version: command.rule_version,
          created_at: values[:created_at]
        )
        key(:plan).failure("must preserve the exact obligation decision") unless event == expected
      end
    end
  end
end
