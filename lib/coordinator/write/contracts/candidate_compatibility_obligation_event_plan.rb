# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateCompatibilityObligationEventPlan < Dry::Validation::Contract
      params do
        required(:plan).value(Types.Instance(Domain::EventPlan))
        required(:state).value(Types.Instance(Domain::CandidateObligations::State))
        required(:command).value(Types.Instance(Commands::CreateCandidateCompatibilityObligation))
      end

      rule(:plan, :state, :command) do
        state = values[:state]
        command = values[:command]
        policy = state.policy.evidence
        reasons = CandidateObligations::Matcher.new.call(source: state.source, target: state.target)
        stream = StreamFactory.new.verification_obligation(command.obligation_id)
        expected = [
          Events::VerificationObligationCreatedV2.new(
            obligation_id: command.obligation_id,
            kind: "candidate_compatibility",
            enforcement: policy.enforcement,
            reasons: reasons.map(&:kind),
            required_evidence: policy.required_evidence
          ),
          Events::VerificationObligationAddedToChangeSetV1.new(
            obligation_id: command.obligation_id,
            change_set_id: state.source.subject.change_set_id
          ),
          Events::VerificationObligationSourceCandidateAssignedV1.new(
            obligation_id: command.obligation_id,
            candidate_id: state.source.subject.candidate_id
          ),
          Events::VerificationObligationTargetCandidateAssignedV1.new(
            obligation_id: command.obligation_id,
            candidate_id: state.target.subject.candidate_id
          )
        ]
        plan = values[:plan]
        unless !state.existing && policy && !reasons.empty? &&
               plan.events == expected &&
               plan.writes.map(&:stream) == Array.new(4, stream)
          key(:plan).failure("must contain the four exact cohesive obligation facts")
        end
      end
    end
  end
end
