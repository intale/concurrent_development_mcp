# frozen_string_literal: true

module Coordinator::Write
  module Contracts
    class AgentChoiceImpactAssessmentCommand < Dry::Validation::Contract
      params do
        required(:command).value(Types.Instance(Commands::AssessAgentChoiceDecisionImpact))
        required(:authoritative_change).value(Types.Instance(AgentChoiceImpacts::DecisionChangeEvidenceV2))
      end

      rule(:command, :authoritative_change) do
        command = values[:command]
        change = values[:authoritative_change]
        accepted = command.accepted_choice
        source = change.source_event

        key(:command).failure("command ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(command.command_id)
        key(:command).failure("assessment ID must be UUIDv7") unless Types::UUID_V7_PATTERN.match?(command.assessment_id)
        unless command.choice_id == accepted.stream_id &&
               accepted.type == "AgentChoiceAccepted" &&
               accepted.stream_context == "AgentGovernance" &&
               accepted.stream_name == "AgentChoice"
          key(:command).failure("accepted Choice reference must identify the target Choice")
        end
        key(:command).failure("Decision change must match authoritative evidence") unless command.decision_change == change
        unless source.stream_context == "HumanGuidance" &&
               source.stream_name == "Decision" &&
               source.stream_id == change.decision_id &&
               source.type == (change.change_kind == "activated" ? "DecisionActivated" : "DecisionDefinitionCorrected")
          key(:command).failure("Decision change reference must identify its exact lifecycle head")
        end
      end
    end
  end
end
