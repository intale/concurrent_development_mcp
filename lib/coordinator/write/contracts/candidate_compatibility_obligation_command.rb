# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class CandidateCompatibilityObligationCommand < Dry::Validation::Contract
      ACTOR_ID = "candidate-impact-obligation-policy"

      params do
        required(:command).value(Types.Instance(Commands::CreateCandidateCompatibilityObligation))
        required(:source).value(Types.Instance(CandidateObligations::CandidateEvidenceV2))
        required(:target).value(Types.Instance(CandidateObligations::CandidateEvidenceV2))
        required(:natural_key).value(Types.Instance(CandidateObligations::NaturalKeyV1))
      end

      rule(:command, :source, :target, :natural_key) do
        command = values[:command]
        source = values[:source]
        target = values[:target]
        natural_key = values[:natural_key]
        unless command.actor.kind == "system" && command.actor.id == ACTOR_ID
          key(:command).failure("actor must be the Candidate-impact obligation policy")
        end
        key(:command).failure("command ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(command.command_id)
        key(:command).failure("obligation ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(command.obligation_id)
        unless command.source_registration == source.registration_event &&
               command.target_registration == target.registration_event
          key(:command).failure("registration references must match the exact Candidate evidence")
        end
        unless source.subject.change_set_id == target.subject.change_set_id &&
               source.subject.candidate_id != target.subject.candidate_id
          key(:command).failure("Candidates must be distinct members of one ChangeSet")
        end
        unless valid_partition_reference?(command, source.subject.change_set_id)
          key(:command).failure("policy reference must identify the exact ChangeSet Candidate partition")
        end
        key(:command).failure("policy head must identify an exact Decision lifecycle event") unless valid_head?(command)
        unless natural_key.document.rule_version == command.rule_version &&
               natural_key.document.policy_head == command.policy_head
          key(:command).failure("natural key must retain the command policy and rule")
        end
      end

      private

      def valid_partition_reference?(command, change_set_id)
        reference = command.policy_partition_event
        expected_id = "changeset:#{change_set_id}:candidate"
        %w[DecisionAddedToPartition DecisionRemovedFromPartition].include?(reference.type) &&
          reference.stream_context == "HumanGuidance" &&
          reference.stream_name == "DecisionPartition" &&
          reference.stream_id == expected_id
      end

      def valid_head?(command)
        head = command.policy_head
        reference = head.event
        head.decision_revision == reference.stream_revision &&
          reference.stream_context == "HumanGuidance" &&
          reference.stream_name == "Decision" &&
          reference.stream_id == head.decision_id &&
          %w[DecisionActivated DecisionDefinitionCorrected].include?(reference.type)
      end
    end
  end
end
