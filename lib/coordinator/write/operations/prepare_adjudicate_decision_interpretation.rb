# frozen_string_literal: true

module Coordinator::Write
  module Operations
    class PrepareAdjudicateDecisionInterpretation < Dry::Operation
      def initialize(contract: Contracts::AdjudicateDecisionInterpretation.new)
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
          Commands::AdjudicateDecisionInterpretation.new(
            command_id: attributes.fetch(:command_id),
            actor: Commands::Actor.new(kind: actor.fetch(:kind), id: actor.fetch(:id)),
            source_message_id: attributes.fetch(:source_message_id),
            interpretation_id: attributes.fetch(:interpretation_id),
            action: attributes.fetch(:action),
            rationale: Interpretations::AdjudicationRationaleV1.new(attributes.fetch(:rationale)),
            clarification: build_clarification(attributes.fetch(:clarification))
          )
        )
      end

      def validate(input)
        result = @contract.call(input)
        return Success(result.to_h) if result.success?

        Failure(
          OutcomeError.new(
            code: :invalid_input,
            message: "AdjudicateDecisionInterpretation input is invalid",
            details: result.errors.to_h
          )
        )
      end

      def build_clarification(attributes)
        return unless attributes

        Interpretations::AdjudicationClarificationV1.new(
          status: attributes.fetch(:status),
          questions: attributes.fetch(:questions).map do |question|
            Interpretations::ClarificationQuestionV1.new(question)
          end
        )
      end
    end
  end
end
