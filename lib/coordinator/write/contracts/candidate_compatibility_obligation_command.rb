# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateCompatibilityObligationCommand < Dry::Validation::Contract
      ACTOR_ID = "candidate-impact-obligation-policy"

      params do
        required(:command).value(Types.Instance(Commands::CreateCandidateCompatibilityObligation))
        required(:source).value(Types.Instance(CandidateObligations::CandidateEvidenceV1))
        required(:target).value(Types.Instance(CandidateObligations::CandidateEvidenceV1))
        required(:expected_identity).value(Types.Instance(CandidateObligations::IdentityV1))
      end

      rule(:command, :source, :target, :expected_identity) do
        command = values[:command]
        source = values[:source]
        target = values[:target]
        identity = values[:expected_identity]
        unless command.actor.kind == "system" && command.actor.id == ACTOR_ID
          key(:command).failure("actor must be the Candidate-impact obligation policy")
        end
        unless command.command_id == identity.obligation_id &&
               command.obligation_id == identity.obligation_id
          key(:command).failure("command and obligation IDs must match the canonical identity")
        end
        unless command.source_registration == source.registration_event &&
               command.target_registration == target.registration_event
          key(:command).failure("registration references must match the exact Candidate evidence")
        end
        unless source.subject.change_set_id == target.subject.change_set_id &&
               source.subject.candidate_id != target.subject.candidate_id
          key(:command).failure("Candidates must be distinct members of one ChangeSet")
        end
        validate_partition_reference(command, source.subject.change_set_id)
        validate_head(command)
        unless identity.document.rule_version == command.rule_version &&
               identity.document.policy_head == command.policy_head
          key(:command).failure("canonical identity must retain the command policy and rule")
        end
      end

      private

      def validate_partition_reference(command, change_set_id)
        reference = command.policy_partition_event
        expected_id = "changeset:#{change_set_id}:candidate"
        valid = reference.type == "DecisionPartitionAdvanced" &&
                reference.stream_context == "HumanGuidance" &&
                reference.stream_name == "DecisionPartition" &&
                reference.stream_id == expected_id
        key(:command).failure("policy reference must identify the exact ChangeSet Candidate partition") unless valid
      end

      def validate_head(command)
        head = command.policy_head
        reference = head.event
        valid = head.decision_revision == reference.stream_revision &&
                reference.stream_context == "HumanGuidance" &&
                reference.stream_name == "Decision" &&
                reference.stream_id == head.decision_id &&
                %w[DecisionActivated DecisionDefinitionCorrected].include?(reference.type)
        key(:command).failure("policy head must identify an exact Decision lifecycle event") unless valid
      end
    end
  end
end
