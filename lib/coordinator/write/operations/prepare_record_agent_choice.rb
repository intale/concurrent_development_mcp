# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareRecordAgentChoice < Dry::Operation
      def initialize(contract: Contracts::RecordAgentChoice.new)
        @contract = contract
      end

      def call(input)
        attributes = step validate(input)
        step build_command(attributes)
      end

      private

      def build_command(attributes)
        actor = attributes.fetch(:actor)

        Success(
          Commands::RecordAgentChoice.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            choice_id: attributes.fetch(:choice_id),
            choice_type: attributes.fetch(:choice_type),
            selected: option(attributes.fetch(:selected)),
            alternatives: attributes.fetch(:alternatives)
              .sort_by { _1.fetch(:option_id).b }
              .map { option(_1) },
            reason_summary: attributes.fetch(:reason_summary),
            context: query_context(attributes.fetch(:context)),
            decision_context: DecisionContexts::ContextV1.new(attributes.fetch(:decision_context))
          )
        )
      end

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "RecordAgentChoice input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def option(attributes)
        AgentChoices::ChoiceOptionV1.new(
          option_id: attributes.fetch(:option_id),
          summary: attributes.fetch(:summary)
        )
      end

      def query_context(attributes)
        DecisionContexts::QueryContextV1.new(
          workspace_id: attributes[:workspace_id],
          repository_id: attributes.fetch(:repository_id),
          change_set_id: attributes.fetch(:change_set_id),
          work_item_id: attributes.fetch(:work_item_id),
          attempt_id: attributes.fetch(:attempt_id),
          phase: attributes.fetch(:phase),
          language: attributes.fetch(:language),
          paths: attributes.fetch(:paths).uniq.sort_by(&:b),
          environment: attributes[:environment],
          agent_role: attributes.fetch(:agent_role)
        )
      end
    end
  end
end
